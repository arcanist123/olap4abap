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
"! - with the period's members restricted to the regular periods of K4 (restrict members, I CP '*001' to I CP '*012',
"!   K4's months): BW's SID table has period 000 and the special periods 013 to 016 of every year, which the
"!   positional time functions (Lag, ParallelPeriod) would count;
"! - with the year and the period marked as time (TimeDimension), the period only with its members restricted.
"! The period's restriction holds only while the facts agree: the probe (ZZXXMLA1_CL_SCHEMA_PROBE) of the facts under
"! K4 refuses it when they hold period 000 or a special period. Then the period is neither restricted nor time in this
"! cube (its time is 0CALMONTH, derived from the period by the model, not by this proposal), and a note says why.
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
    "! The fiscal defaults a provider would get, unchecked: the variant fixed, the period's members restricted to
    "! the regular periods and the time characteristics; initial without 0FISCYEAR or 0FISCPER compounded with
    "! 0FISCVARNT.
    CLASS-METHODS fiscal_defaults
      IMPORTING provider      TYPE zzxxmla1_cl_bw_provider=>ty_provider
      RETURNING VALUE(result) TYPE ty_defaults.
    "! The rows of the regular periods 001 to 012 of every fiscal year: I CP '*001', ...
    CLASS-METHODS regular_periods
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_selection=>ty_t_row.

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA reader TYPE REF TO zzxxmla1_cl_bw_provider.

    "! The probe's excluded values as text: K4/2024013 (5 facts), ...
    CLASS-METHODS values_text
      IMPORTING !values       TYPE zzxxmla1_cl_schema_probe=>ty_t_value
      RETURNING VALUE(result) TYPE string.
ENDCLASS.



CLASS zzxxmla1_cl_schema_defaults IMPLEMENTATION.

  METHOD constructor.
    reader = NEW zzxxmla1_cl_bw_provider( ).
  ENDMETHOD.

  METHOD propose.
    result = fiscal_defaults( provider ).
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
    IF NOT line_exists( result-selection[ iobjnm = '0FISCPER' ] ).
      RETURN.
    ENDIF.
    " the facts under K4 must hold regular periods only
    DATA(probed) = NEW zzxxmla1_cl_schema_probe( )->probe( provider = provider-name selection = result-selection ).
    READ TABLE probed INTO DATA(period) WITH KEY name = `0FISCPER`.
    IF sy-subrc = 0 AND period-ok = abap_false.
      DELETE result-selection WHERE iobjnm = '0FISCPER'.
      DELETE result-time WHERE table_line = `0FISCPER`.
      APPEND VALUE #( iobjnm = `0FISCPER`
                      reason = |not a time dimension in this cube: its facts under { c_variant } hold period 000 or | &&
                               |special periods ({ values_text( period-values ) }), which the time functions would | &&
                               |count; use 0CALMONTH as time| ) TO result-notes.
      RETURN.
    ENDIF.
    APPEND VALUE #( iobjnm = `0FISCPER`
                    reason = |members restricted to the regular periods and marked as time| ) TO result-notes.
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
      IF characteristic-iobjnm = `0FISCPER`.
        INSERT VALUE #( iobjnm = '0FISCPER'
                        mode   = zzxxmla1_cl_bw_selection=>c_mode-members
                        rows   = regular_periods( ) ) INTO TABLE result-selection.
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
