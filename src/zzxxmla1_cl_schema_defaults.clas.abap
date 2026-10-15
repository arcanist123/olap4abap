*----------------------------------------------------------------------------------------------------------------------*
* olap4abap - XMLA server with an MDX engine for SAP BW               https://github.com/arcanist123/olap4abap
* Copyright (c) 2026 the olap4abap authors
*
* This program and the accompanying materials are made available under the terms of the Eclipse Public License 2.0,
* which is available at https://www.eclipse.org/legal/epl-2.0/
* SPDX-License-Identifier: EPL-2.0
*
* olap4abap contains code derived from Mondrian (Eclipse Public License 1.0): Copyright (C) 1998-2005 Julian Hyde,
* Copyright (C) 2005-2021 Hitachi Vantara and others, Copyright (C) 2021-2025 Sergei Semenkov. See the NOTICE file.
*----------------------------------------------------------------------------------------------------------------------*
"! What a proposal restricts and marks as time by default (docs/bw-schema-design-guide.md, section 3.8, fiscal time):
"! a provider with BW's fiscal year 0FISCYEAR or fiscal period 0FISCPER (compounded with the fiscal year variant
"! 0FISCVARNT) is proposed
"! - with the variant fixed to K4 (filter the cube with I EQ 'K4'; the most common variant, the user changes it on the
"!   variant's dimension), so the year and the period are named by their own keys (2024001);
"! - with the period's members restricted to the regular periods of K4 (restrict members, K4's months are 001 to
"!   012): BW's SID table has period 000 and the special periods 013 to 016 of every year, which the positional time
"!   functions (Lag, ParallelPeriod) would count;
"! - with the members of year and period restricted to BW's interval of the virtual time hierarchies
"!   (RSRHIERARCHYVIRT, table RSADMINS, ZZXXMLA1_CL_TIME_MD=>interval), the interval the time master data is filled
"!   for: I BT '1995' '2029', and I BT '1995010' '2029012' with E CP '*000' and E CP '*013' to E CP '*016'. A time
"!   dimension has every member of its view, not only those with facts (members with facts is not supported on time),
"!   and BW's SID table also holds the values loaded or converted outside the interval;
"! - with the year and the period marked as time (TimeDimension), the period only with its members restricted.
"! The restrictions hold only while the facts agree (ZZXXMLA1_CL_SCHEMA_PROBE): when the facts under K4 hold period
"! 000 or a special period, the period is neither restricted nor time in this cube (its time is 0CALMONTH, derived
"! from the period by the model, not by this proposal); when they hold a year or period outside the interval, its
"! members are not restricted to the interval (the period's to the regular periods still). A note says why.
"! Nothing is restricted if K4 cannot be fixed (no SID of K4, or a characteristic that references 0FISCVARNT); a note
"! says why. Other providers get no defaults. Nothing is written.
CLASS zzxxmla1_cl_schema_defaults DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! the fiscal year variant proposed
    CONSTANTS c_variant TYPE c LENGTH 2 VALUE 'K4'.
    "! its regular periods, one per month
    CONSTANTS c_regular_periods TYPE i VALUE 12.
    TYPES:
      "! the selection a proposal restricts the cube by, the characteristics it marks as time and the notes on both
      BEGIN OF ty_defaults,
        selection TYPE zzxxmla1_cl_bw_view_gen=>ty_t_selection,
        time      TYPE string_table,
        notes     TYPE zzxxmla1_cl_bw_provider=>ty_t_note,
      END OF ty_defaults.

    METHODS constructor.
    "! The defaults of a provider read without selection, checked and probed.
    METHODS propose
      IMPORTING provider      TYPE zzxxmla1_cl_bw_provider=>ty_provider
      RETURNING VALUE(result) TYPE ty_defaults.
    "! The fiscal defaults a provider would get, unchecked: the variant fixed, the members of year and period
    "! restricted to the interval (interval_rows), the period's to the regular periods also without interval, and
    "! the time characteristics; initial without 0FISCYEAR or 0FISCPER compounded with 0FISCVARNT.
    CLASS-METHODS fiscal_defaults
      IMPORTING provider      TYPE zzxxmla1_cl_bw_provider=>ty_provider
                !interval     TYPE zzxxmla1_cl_time_md=>ty_interval OPTIONAL
      RETURNING VALUE(result) TYPE ty_defaults.
    "! The rows of the regular periods 001 to 012 of every fiscal year: I CP '*001', ...
    CLASS-METHODS regular_periods
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_selection=>ty_t_row.
    "! The rows of the values of a fiscal characteristic in an interval, under K4: 0FISCYEAR I BT '1995' '2029',
    "! 0FISCPER the regular periods I BT '1995010' '2029012', E CP '*000', E CP '*013' ... E CP '*016'; initial for
    "! another characteristic or without interval.
    CLASS-METHODS interval_rows
      IMPORTING iobjnm        TYPE csequence
                !interval     TYPE zzxxmla1_cl_time_md=>ty_interval
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_selection=>ty_t_row.

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA reader TYPE REF TO zzxxmla1_cl_bw_provider.
    DATA probe TYPE REF TO zzxxmla1_cl_schema_probe.

    "! The interval as text: 1995-10-01 to 2029-12-31
    CLASS-METHODS interval_text
      IMPORTING !interval     TYPE zzxxmla1_cl_time_md=>ty_interval
      RETURNING VALUE(result) TYPE string.

    "! The probe's excluded values as text: K4/2024013 (5 facts), ...
    CLASS-METHODS values_text
      IMPORTING !values       TYPE zzxxmla1_cl_schema_probe=>ty_t_value
      RETURNING VALUE(result) TYPE string.
ENDCLASS.



CLASS zzxxmla1_cl_schema_defaults IMPLEMENTATION.

  METHOD constructor.
    reader = NEW zzxxmla1_cl_bw_provider( ).
    probe = NEW zzxxmla1_cl_schema_probe( ).
  ENDMETHOD.

  METHOD propose.
    DATA(interval) = NEW zzxxmla1_cl_time_md( )->interval( ).
    result = fiscal_defaults( provider = provider interval = interval ).
    IF result-selection IS INITIAL.
      RETURN.
    ENDIF.
    " K4 must have a SID, and 0FISCVARNT no characteristic that references it (they would share the filtered view)
    TRY.
        reader->check_selection( reader->read( name = provider-name selection = result-selection ) ).
      CATCH zzxxmla1_cx_bw_provider INTO DATA(error).
        result = VALUE #( notes = VALUE #( ( iobjnm = `0FISCVARNT`
                                             reason = |not fixed to { c_variant }: { error->get_text( ) }| ) ) ).
        RETURN.
    ENDTRY.
    APPEND VALUE #( iobjnm = `0FISCVARNT`
                    reason = |fixed to { c_variant }, the most common variant: change it on its dimension| )
      TO result-notes.
    " the facts under K4 must hold regular periods only
    IF line_exists( result-selection[ iobjnm = '0FISCPER' ] ).
      DATA(regular) = VALUE zzxxmla1_cl_bw_view_gen=>ty_t_selection(
        ( result-selection[ iobjnm = '0FISCVARNT' ] )
        ( iobjnm = '0FISCPER' mode = zzxxmla1_cl_bw_selection=>c_mode-members rows = regular_periods( ) ) ).
      DATA(periods) = probe->probe( provider = provider-name selection = regular ).
      READ TABLE periods INTO DATA(period) WITH KEY name = `0FISCPER`.
      IF sy-subrc = 0 AND period-ok = abap_false.
        DELETE result-selection WHERE iobjnm = '0FISCPER'.
        DELETE result-time WHERE table_line = `0FISCPER`.
        APPEND VALUE #( iobjnm = `0FISCPER`
                        reason = |not a time dimension in this cube: its facts under { c_variant } hold period 000 | &&
                                 |or special periods ({ values_text( period-values ) }), which the time functions | &&
                                 |would count; use 0CALMONTH as time| ) TO result-notes.
      ENDIF.
    ENDIF.
    " and lie in BW's interval
    DATA(in_interval) = |BW's interval of RSRHIERARCHYVIRT ({ interval_text( interval ) })|.
    DATA(probed) = probe->probe( provider = provider-name selection = result-selection ).
    LOOP AT result-time INTO DATA(time).
      DATA(prefix) = COND string( WHEN time = `0FISCPER` THEN `members restricted to the regular periods and`
                                  ELSE `members restricted` ).
      READ TABLE probed INTO DATA(outside) WITH KEY name = time.
      IF sy-subrc <> 0 OR outside-ok = abap_true.
        APPEND VALUE #( iobjnm = time reason = |{ prefix } to { in_interval }, marked as time| ) TO result-notes.
        CONTINUE.
      ENDIF.
      DATA(reason) = |not to { in_interval }: its facts hold values outside it ({ values_text( outside-values ) }), | &&
                     |widen it in RSRHIERARCHYVIRT; marked as time|.
      IF time = `0FISCPER`.
        result-selection[ iobjnm = '0FISCPER' ]-rows = regular_periods( ).
        reason = |members restricted to the regular periods, { reason }|.
      ELSE.
        DELETE result-selection WHERE iobjnm = CONV rsiobjnm( time ).
        reason = |members not restricted, { reason }|.
      ENDIF.
      APPEND VALUE #( iobjnm = time reason = reason ) TO result-notes.
    ENDLOOP.
  ENDMETHOD.

  METHOD fiscal_defaults.
    IF NOT line_exists( provider-characteristics[ iobjnm = `0FISCVARNT` has_sids = abap_true ] ).
      RETURN.
    ENDIF.
    LOOP AT provider-characteristics INTO DATA(characteristic)
         WHERE ( iobjnm = `0FISCYEAR` OR iobjnm = `0FISCPER` ) AND has_sids = abap_true.
      IF NOT line_exists( characteristic-compounding[ table_line = `0FISCVARNT` ] ).
        CONTINUE.
      ENDIF.
      DATA(rows) = interval_rows( iobjnm = characteristic-iobjnm interval = interval ).
      IF rows IS INITIAL AND characteristic-iobjnm = `0FISCPER`.
        rows = regular_periods( ).
      ENDIF.
      IF rows IS NOT INITIAL.
        INSERT VALUE #( iobjnm = characteristic-iobjnm
                        mode   = zzxxmla1_cl_bw_selection=>c_mode-members
                        rows   = rows ) INTO TABLE result-selection.
      ENDIF.
      APPEND characteristic-iobjnm TO result-time.
    ENDLOOP.
    IF result-time IS INITIAL.
      RETURN.
    ENDIF.
    INSERT VALUE #( iobjnm = '0FISCVARNT'
                    mode   = zzxxmla1_cl_bw_selection=>c_mode-filter
                    rows   = zzxxmla1_cl_bw_selection=>equals( c_variant ) ) INTO TABLE result-selection.
  ENDMETHOD.

  METHOD interval_rows.
    IF interval-from IS INITIAL OR interval-to IS INITIAL.
      RETURN.
    ENDIF.
    CASE iobjnm.
      WHEN `0FISCYEAR`.
        result = VALUE #( ( sign = 'I' option = 'BT' low = interval-from(4) high = interval-to(4) ) ).
      WHEN `0FISCPER`.
        " K4: a month's period is its number
        result = VALUE #( ( sign = 'I' option = 'BT' low  = |{ interval-from(4) }0{ interval-from+4(2) }|
                                                     high = |{ interval-to(4) }0{ interval-to+4(2) }| )
                          ( sign = 'E' option = 'CP' low = `*000` ) ).
        DO 4 TIMES.
          APPEND VALUE #( sign = 'E' option = 'CP'
                          low  = |*{ c_regular_periods + sy-index WIDTH = 3 ALIGN = RIGHT PAD = '0' }| ) TO result.
        ENDDO.
    ENDCASE.
  ENDMETHOD.

  METHOD interval_text.
    result = |{ interval-from DATE = ISO } to { interval-to DATE = ISO }|.
  ENDMETHOD.

  METHOD regular_periods.
    DO c_regular_periods TIMES.
      APPEND VALUE #( sign = 'I' option = 'CP' low = |*{ sy-index WIDTH = 3 ALIGN = RIGHT PAD = '0' }| ) TO result.
    ENDDO.
  ENDMETHOD.

  METHOD values_text.
    DATA texts TYPE string_table.
    LOOP AT values INTO DATA(value).
      APPEND |{ value-value } ({ value-facts } facts)| TO texts.
    ENDLOOP.
    result = concat_lines_of( table = texts sep = `, ` ).
  ENDMETHOD.

ENDCLASS.
