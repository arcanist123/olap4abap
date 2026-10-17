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
"! The master data of BW's calendar time characteristics for a time interval (docs/time-master-data.md): a SID for
"! every value of the interval (SID table /BI0/S...) and an attribute row for every value with a SID (attribute table
"! /BI0/P...: DATEFROM, DATETO, NUMDAY, NUMWDAY and the year, month or quarter it belongs to), so the views of the
"! characteristics (ZZXXMLA1_CL_BW_VIEW_GEN) have every period as a member, with its attributes.
"! BW fills neither by itself: SIDs are made only for the values that are loaded, and the button of RSRHIERARCHYVIRT
"! (CL_RS_TIME_SERVICE=>REBUILD_TIME_MD_TABLES) fills only 0DATE, 0CALMONTH, 0CALQUARTER and 0FISCPER, and these only
"! if they have a navigation attribute (in the standard all their attributes are display attributes).
"! The interval is BW's, the one of the virtual time hierarchies (RSADMINS, RSRHIERARCHYVIRT), unless given; the
"! working days are counted in its factory calendar. SIDs are made by BW (RRSI_VAL_SID_CONVERT), the attribute rows
"! are written here. 0CALDAY is not filled.
"! The fiscal characteristics 0FISCYEAR and 0FISCPER are compounded with the fiscal year variant: their values are the
"! variant and the key (K42024001), shown with a / (K4/2024001). They are filled as 0CALYEAR and 0CALMONTH are, for the
"! variant K4 (c_fiscal_variant), whose fiscal year is the calendar year and whose periods 001 to 012 are its months:
"! every year and every period of the interval. BW's SID conversion of a period also makes period 000 and the special
"! periods 013 to 016 of its year; their attribute rows have the year and FISCPER3, no dates.
"! The texts (text table /BI0/T...: 0CALMONTH, 0CALQUARTER, 0CALMONTH2, 0CALQUART1, 0WEEKDAY1, 0FISCYEAR) are written in
"! English, the language of the views, for every value with a SID and the initial value, as BW's readers of these
"! characteristics make them when a query asks (CL_RSMD_RS_0CALMONTH, ..._0CALMONTH2, ..._0CALQUART1, ..._0WEEKDAY1):
"! the month names of T247 (JAN 1997, January 1997), the weekday names of T246, the quarter of the text pool of
"! SAPLRRSV (Q1 1997, Quarter 1 1997) and Not assigned for the initial value; BW does not write them to the tables.
CLASS zzxxmla1_cl_time_md DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! the fiscal year variant 0FISCYEAR and 0FISCPER are filled for: the fiscal year is the calendar year, the
    "! periods 001 to 012 are its months, 013 to 016 its special periods
    CONSTANTS c_fiscal_variant TYPE c LENGTH 2 VALUE 'K4'.
    "! the language of the texts written, the one the views read (ZZXXMLA1_CL_BW_VIEW_GEN)
    CONSTANTS c_language TYPE c LENGTH 1 VALUE 'E'.
    TYPES:
      BEGIN OF ty_interval,
        from     TYPE d,
        to       TYPE d,
        calendar TYPE c LENGTH 2,  " factory calendar of the working days
      END OF ty_interval.
    TYPES:
      "! a time characteristic this class fills
      BEGIN OF ty_characteristic,
        name            TYPE string,  " 0CALMONTH
        sid_table       TYPE string,
        attribute_table TYPE string,  " initial: no master data, SIDs only
        text_table      TYPE string,  " initial: no texts
        key_field       TYPE string,
        length          TYPE i,       " of the key (NUMC)
        compounding     TYPE string,  " the variant's field of a fiscal characteristic (FISCVARNT), else initial
      END OF ty_characteristic,
      ty_t_characteristic TYPE STANDARD TABLE OF ty_characteristic WITH EMPTY KEY.
    TYPES:
      "! how complete the tables of a characteristic are; the initial value (SID 0) is not counted
      BEGIN OF ty_status,
        characteristic     TYPE ty_characteristic,
        sids               TYPE i,       " values with a SID
        attributes         TYPE i,       " active attribute rows
        expected           TYPE i,       " values of the interval
        missing_sids       TYPE i,       " values of the interval without SID
        missing_attributes TYPE i,       " values of the interval or with a SID, without attribute row
        texts              TYPE i,       " text rows in c_language
        missing_texts      TYPE i,       " values of the interval or with a SID, without text row
        first             TYPE string,  " the smallest value with a SID (K4/2024001 for a fiscal one)
        last               TYPE string,  " the largest
        "! its tables this system does not have: without SID table the characteristic is not active, nothing is
        "! read or filled; without attribute or text table no attribute rows or texts
        missing_tables     TYPE string_table,
      END OF ty_status,
      ty_t_status TYPE STANDARD TABLE OF ty_status WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_fill_result,
        name           TYPE string,
        created_sids   TYPE i,
        attribute_rows TYPE i,       " written (inserted or replaced)
        text_rows      TYPE i,       " written (inserted or replaced), the initial value's too
        error          TYPE string,  " the characteristic was not (completely) filled
        warning        TYPE string,  " filled, but not all of it (no attribute or text table)
      END OF ty_fill_result,
      ty_t_fill_result TYPE STANDARD TABLE OF ty_fill_result WITH EMPTY KEY.
    TYPES:
      "! the values a characteristic misses, as the page shows them (K4/2024001)
      BEGIN OF ty_missing,
        name       TYPE string,
        error      TYPE string,        " not a characteristic this class fills
        sids       TYPE string_table,  " values of the interval without SID
        attributes TYPE string_table,  " values of the interval or with a SID, without attribute row
        texts      TYPE string_table,  " values of the interval or with a SID, without text row
      END OF ty_missing.

    "! The characteristics this class fills, in the order of the UI.
    CLASS-METHODS characteristics
      RETURNING VALUE(result) TYPE ty_t_characteristic.
    "! BW's interval of the virtual time hierarchies (RSADMINS) and its factory calendar; if it is not set, BW's
    "! default (CL_RSR_HIERARCHY_VIRT: seven years back, ten ahead).
    METHODS interval
      RETURNING VALUE(result) TYPE ty_interval.
    METHODS status
      IMPORTING !interval     TYPE ty_interval
      RETURNING VALUE(result) TYPE ty_t_status.
    "! Makes the SIDs of the interval's values and writes the attribute rows of every value with a SID, one
    "! characteristic after the other, each committed. Without names all characteristics; an unknown name is a
    "! result with an error.
    METHODS fill
      IMPORTING !interval     TYPE ty_interval
                !names        TYPE string_table OPTIONAL
      RETURNING VALUE(result) TYPE ty_t_fill_result.
    "! The values of the characteristic that miss a SID, an attribute row or a text row; only values this class can
    "! fill count (a value of another fiscal year variant than K4 does not).
    METHODS missing
      IMPORTING !interval     TYPE ty_interval
                !name         TYPE string
      RETURNING VALUE(result) TYPE ty_missing.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES ty_value TYPE c LENGTH 10.
    TYPES ty_t_value TYPE SORTED TABLE OF ty_value WITH UNIQUE KEY table_line.
    TYPES:
      "! the attributes of a value: its period and what it belongs to; a special period has no dates
      BEGIN OF ty_period,
        known    TYPE abap_bool,  " the value is one of the characteristic
        from     TYPE d,
        to       TYPE d,
        year     TYPE n LENGTH 4,
        month2   TYPE n LENGTH 2,
        quarter1 TYPE n LENGTH 1,
        fiscper3 TYPE n LENGTH 3,
      END OF ty_period.
    TYPES:
      "! a row of a fiscal characteristic's table: the variant and the key
      BEGIN OF ty_compound,
        compounding TYPE c LENGTH 2,
        key         TYPE c LENGTH 8,
      END OF ty_compound,
      ty_t_compound TYPE STANDARD TABLE OF ty_compound WITH EMPTY KEY.
    TYPES:
      "! the texts of a value; not known if the value is none
      BEGIN OF ty_texts,
        known  TYPE abap_bool,
        short  TYPE string,
        medium TYPE string,
        long   TYPE string,
      END OF ty_texts.
    TYPES:
      "! a month's or weekday's names
      BEGIN OF ty_name,
        number TYPE i,
        short  TYPE string,
        long   TYPE string,
      END OF ty_name,
      ty_t_name TYPE SORTED TABLE OF ty_name WITH UNIQUE KEY number.
    TYPES:
      "! what the texts are made of, in c_language
      BEGIN OF ty_labels,
        months        TYPE ty_t_name,  " T247
        weekdays      TYPE ty_t_name,  " T246
        quarter_short TYPE string,     " Q (text pool of SAPLRRSV, Q01)
        quarter_long  TYPE string,     " Quarter (Q02)
        not_assigned  TYPE string,     " the initial value's (text pool of SAPLRSDM, 001)
      END OF ty_labels.
    TYPES:
      "! the state of a characteristic and the values it misses
      BEGIN OF ty_analysis,
        status             TYPE ty_status,
        missing_sids       TYPE ty_t_value,
        missing_attributes TYPE ty_t_value,
        missing_texts      TYPE ty_t_value,
      END OF ty_analysis.

    DATA label_buffer TYPE ty_labels.

    "! The values of a characteristic in the interval: every period that overlaps it; the values of a characteristic
    "! without year (0CALMONTH2, ...) all of them; a fiscal one as the variant K4 and the key (K42024001).
    CLASS-METHODS values
      IMPORTING !name         TYPE string
                !interval     TYPE ty_interval
      RETURNING VALUE(result) TYPE ty_t_value.
    "! The period of a value of 0CALYEAR, 0CALQUARTER, 0CALMONTH, 0CALWEEK, 0FISCYEAR or 0FISCPER (K42024001: a
    "! regular period its month's dates, period 000 or a special one the year and FISCPER3 only); not known if the
    "! value is none (another variant than K4 too).
    CLASS-METHODS period
      IMPORTING !name         TYPE string
                !value        TYPE csequence
      RETURNING VALUE(result) TYPE ty_period.
    "! The value of a fiscal characteristic's row: the variant in its two characters, then the key.
    CLASS-METHODS compound_value
      IMPORTING !row          TYPE ty_compound
      RETURNING VALUE(result) TYPE ty_value.
    "! The texts of a value of a characteristic with texts, as BW's reader of the characteristic makes them; the
    "! initial value Not assigned.
    CLASS-METHODS texts
      IMPORTING !name         TYPE string
                !value        TYPE csequence
                !labels       TYPE ty_labels
      RETURNING VALUE(result) TYPE ty_texts.
    "! A text symbol of a text pool as BW reads it, into a field of the width (characters past it are dropped);
    "! the default if the pool has none.
    CLASS-METHODS text_symbol
      IMPORTING !pool         TYPE textpool_table
                !key          TYPE csequence
                !width        TYPE i
                !default      TYPE string
      RETURNING VALUE(result) TYPE string.
    "! The initial value: zeros, a fiscal one without variant.
    CLASS-METHODS initial_value
      IMPORTING characteristic TYPE ty_characteristic
      RETURNING VALUE(result)  TYPE ty_value.
    "! A value as the page shows it: a fiscal one as K4/2024001.
    CLASS-METHODS display
      IMPORTING characteristic TYPE ty_characteristic
                !value         TYPE ty_value
      RETURNING VALUE(result)  TYPE string.
    "! The ISO week of a date as 0CALWEEK has it: YYYYWW, the year the week's Thursday is in.
    CLASS-METHODS iso_week
      IMPORTING !date         TYPE d
      RETURNING VALUE(result) TYPE ty_value.
    "! 1 Monday ... 7 Sunday, as 0WEEKDAY1.
    CLASS-METHODS weekday
      IMPORTING !date         TYPE d
      RETURNING VALUE(result) TYPE i.
    CLASS-METHODS last_day_of_month
      IMPORTING !year         TYPE i
                !month        TYPE i
      RETURNING VALUE(result) TYPE d.
    "! The working days of a period in a factory calendar; -1 if the calendar does not cover it.
    METHODS working_days
      IMPORTING !from         TYPE d
                !to           TYPE d
                !calendar     TYPE c
      RETURNING VALUE(result) TYPE i.
    "! The tables of the characteristic (SID and attribute table) that are not active transparent tables of the
    "! dictionary: a characteristic that is not active in BW has neither, not every system has all of them.
    METHODS missing_tables
      IMPORTING characteristic TYPE ty_characteristic
      RETURNING VALUE(result)  TYPE string_table.
    "! The non-initial values of the SID table.
    METHODS sid_values
      IMPORTING characteristic TYPE ty_characteristic
      RETURNING VALUE(result)  TYPE ty_t_value.
    "! The month and weekday names and the quarter's and initial value's texts in c_language, read once.
    METHODS labels
      RETURNING VALUE(result) TYPE ty_labels.
    METHODS analyse
      IMPORTING characteristic TYPE ty_characteristic
                !interval      TYPE ty_interval
      RETURNING VALUE(result)  TYPE ty_analysis.
    "! The non-initial values with a text row in c_language.
    METHODS text_values
      IMPORTING characteristic TYPE ty_characteristic
      RETURNING VALUE(result)  TYPE ty_t_value.
    "! The non-initial values of the active attribute rows.
    METHODS attribute_values
      IMPORTING characteristic TYPE ty_characteristic
      RETURNING VALUE(result)  TYPE ty_t_value.
    METHODS fill_characteristic
      IMPORTING characteristic TYPE ty_characteristic
                !interval      TYPE ty_interval
      RETURNING VALUE(result)  TYPE ty_fill_result.
    "! Makes the SIDs of the values with BW's SID conversion; the error message, initial if it worked.
    METHODS create_sids
      IMPORTING characteristic TYPE ty_characteristic
                !values        TYPE ty_t_value
      RETURNING VALUE(result)  TYPE string.
    "! Writes the text rows of the values in c_language; the rows written.
    METHODS write_texts
      IMPORTING characteristic TYPE ty_characteristic
                !values        TYPE ty_t_value
      RETURNING VALUE(result)  TYPE i.
    "! Sets the key of a row of the characteristic's tables: the key field and a fiscal one's variant.
    CLASS-METHODS set_key
      IMPORTING characteristic TYPE ty_characteristic
                !value         TYPE ty_value
      CHANGING  !line          TYPE any.
    "! Writes the active attribute rows of the values; the rows written.
    METHODS write_attributes
      IMPORTING characteristic TYPE ty_characteristic
                !values        TYPE ty_t_value
                !calendar      TYPE c
      RETURNING VALUE(result)  TYPE i.
ENDCLASS.



CLASS zzxxmla1_cl_time_md IMPLEMENTATION.

  METHOD characteristics.
    result = VALUE #(
      ( name = `0CALYEAR`    sid_table = `/BI0/SCALYEAR`    attribute_table = `/BI0/PCALYEAR`
        key_field = `CALYEAR`    length = 4 )
      ( name = `0CALQUARTER` sid_table = `/BI0/SCALQUARTER` attribute_table = `/BI0/PCALQUARTER`
        text_table = `/BI0/TCALQUARTER` key_field = `CALQUARTER` length = 5 )
      ( name = `0CALMONTH`   sid_table = `/BI0/SCALMONTH`   attribute_table = `/BI0/PCALMONTH`
        text_table = `/BI0/TCALMONTH`   key_field = `CALMONTH`   length = 6 )
      ( name = `0CALWEEK`    sid_table = `/BI0/SCALWEEK`    attribute_table = `/BI0/PCALWEEK`
        key_field = `CALWEEK`    length = 6 )
      ( name = `0HALFYEAR1`  sid_table = `/BI0/SHALFYEAR1`  key_field = `HALFYEAR1` length = 1 )
      ( name = `0CALQUART1`  sid_table = `/BI0/SCALQUART1`  text_table = `/BI0/TCALQUART1`
        key_field = `CALQUART1` length = 1 )
      ( name = `0CALMONTH2`  sid_table = `/BI0/SCALMONTH2`  text_table = `/BI0/TCALMONTH2`
        key_field = `CALMONTH2` length = 2 )
      ( name = `0WEEKDAY1`   sid_table = `/BI0/SWEEKDAY1`   text_table = `/BI0/TWEEKDAY1`
        key_field = `WEEKDAY1`  length = 1 )
      ( name = `0FISCYEAR`   sid_table = `/BI0/SFISCYEAR`   attribute_table = `/BI0/PFISCYEAR`
        text_table = `/BI0/TFISCYEAR` key_field = `FISCYEAR`   length = 4 compounding = `FISCVARNT` )
      ( name = `0FISCPER`    sid_table = `/BI0/SFISCPER`    attribute_table = `/BI0/PFISCPER`
        key_field = `FISCPER`    length = 7 compounding = `FISCVARNT` ) ).
  ENDMETHOD.

  METHOD interval.
    " RSADMINS by name, as CL_RSR_HIERARCHY_VIRT reads it (rscus_c_tabrsadms)
    DATA(table) = `RSADMINS`.
    SELECT SINGLE hierarchyvirtfr, hierarchyvirtto, fcalid
      FROM (table)
      WHERE customizid = 'BW'
      INTO (@result-from, @result-to, @result-calendar).
    IF result-from IS INITIAL AND result-to IS INITIAL.
      result-from = |{ sy-datum(4) - 7 }{ sy-datum+4(2) }01|.
      result-to = |{ sy-datum(4) + 10 }{ sy-datum+4(2) }01|.
    ENDIF.
    IF result-calendar IS INITIAL.
      result-calendar = '01'.
    ENDIF.
  ENDMETHOD.

  METHOD status.
    LOOP AT characteristics( ) INTO DATA(characteristic).
      APPEND analyse( characteristic = characteristic interval = interval )-status TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD missing.
    result-name = name.
    READ TABLE characteristics( ) INTO DATA(characteristic) WITH KEY name = to_upper( name ).
    IF sy-subrc <> 0.
      result-error = |{ name } is not a time characteristic this server fills|.
      RETURN.
    ENDIF.
    result-name = characteristic-name.
    DATA(analysis) = analyse( characteristic = characteristic interval = interval ).
    result-sids = VALUE #( FOR v IN analysis-missing_sids ( display( characteristic = characteristic value = v ) ) ).
    result-attributes = VALUE #( FOR v IN analysis-missing_attributes
                                 ( display( characteristic = characteristic value = v ) ) ).
    result-texts = VALUE #( FOR v IN analysis-missing_texts ( display( characteristic = characteristic value = v ) ) ).
  ENDMETHOD.

  METHOD analyse.
    DATA(expected) = values( name = characteristic-name interval = interval ).
    DATA(missing) = missing_tables( characteristic ).
    result-status = VALUE #( characteristic = characteristic expected = lines( expected ) missing_tables = missing ).
    IF line_exists( missing[ table_line = characteristic-sid_table ] ).
      RETURN.
    ENDIF.
    DATA(sids) = sid_values( characteristic ).
    result-status-sids = lines( sids ).
    LOOP AT expected INTO DATA(value).
      IF NOT line_exists( sids[ table_line = value ] ).
        INSERT value INTO TABLE result-missing_sids.
      ENDIF.
    ENDLOOP.
    result-status-missing_sids = lines( result-missing_sids ).
    IF sids IS NOT INITIAL.
      result-status-first = display( characteristic = characteristic value = sids[ 1 ] ).
      result-status-last = display( characteristic = characteristic value = sids[ lines( sids ) ] ).
    ENDIF.
    " the values that need rows: those with a SID and those of the interval
    DATA(wanted) = sids.
    " one by one: INSERT LINES OF a value already there would end the program
    LOOP AT expected INTO value.
      INSERT value INTO TABLE wanted.
    ENDLOOP.
    IF characteristic-attribute_table IS NOT INITIAL
       AND NOT line_exists( missing[ table_line = characteristic-attribute_table ] ).
      DATA(attributes) = attribute_values( characteristic ).
      result-status-attributes = lines( attributes ).
      LOOP AT wanted INTO value.
        IF period( name = characteristic-name value = value )-known = abap_true
           AND NOT line_exists( attributes[ table_line = value ] ).
          INSERT value INTO TABLE result-missing_attributes.
        ENDIF.
      ENDLOOP.
      result-status-missing_attributes = lines( result-missing_attributes ).
    ENDIF.
    IF characteristic-text_table IS NOT INITIAL
       AND NOT line_exists( missing[ table_line = characteristic-text_table ] ).
      DATA(with_text) = text_values( characteristic ).
      DATA(names) = labels( ).
      result-status-texts = lines( with_text ).
      LOOP AT wanted INTO value.
        IF texts( name = characteristic-name value = value labels = names )-known = abap_true
           AND NOT line_exists( with_text[ table_line = value ] ).
          INSERT value INTO TABLE result-missing_texts.
        ENDIF.
      ENDLOOP.
      result-status-missing_texts = lines( result-missing_texts ).
    ENDIF.
  ENDMETHOD.

  METHOD fill.
    DATA(all) = characteristics( ).
    DATA(wanted) = names.
    IF wanted IS INITIAL.
      wanted = VALUE #( FOR entry IN all ( entry-name ) ).
    ENDIF.
    LOOP AT wanted INTO DATA(name).
      READ TABLE all INTO DATA(characteristic) WITH KEY name = to_upper( name ).
      IF sy-subrc <> 0.
        APPEND VALUE #( name = name error = |{ name } is not a time characteristic this server fills| ) TO result.
        CONTINUE.
      ENDIF.
      APPEND fill_characteristic( characteristic = characteristic interval = interval ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD fill_characteristic.
    result-name = characteristic-name.
    DATA(missing) = missing_tables( characteristic ).
    IF line_exists( missing[ table_line = characteristic-sid_table ] ).
      result-error = |{ characteristic-name } is not active in this system: table { characteristic-sid_table } | &&
                     |does not exist|.
      RETURN.
    ENDIF.
    " without attribute table it is filled as a characteristic without master data: SIDs only, unchecked
    DATA(usable) = characteristic.
    DATA warnings TYPE string_table.
    IF usable-attribute_table IS NOT INITIAL AND line_exists( missing[ table_line = usable-attribute_table ] ).
      APPEND |no attribute rows written: table { usable-attribute_table } does not exist| TO warnings.
      CLEAR usable-attribute_table.
    ENDIF.
    IF usable-text_table IS NOT INITIAL AND line_exists( missing[ table_line = usable-text_table ] ).
      APPEND |no texts written: table { usable-text_table } does not exist| TO warnings.
      CLEAR usable-text_table.
    ENDIF.
    result-warning = concat_lines_of( table = warnings sep = `; ` ).
    DATA(sids) = sid_values( usable ).
    DATA without_sid TYPE ty_t_value.
    LOOP AT values( name = characteristic-name interval = interval ) INTO DATA(value).
      IF NOT line_exists( sids[ table_line = value ] ).
        INSERT value INTO TABLE without_sid.
      ENDIF.
    ENDLOOP.
    IF without_sid IS NOT INITIAL.
      result-error = create_sids( characteristic = usable values = without_sid ).
      IF result-error IS NOT INITIAL.
        ROLLBACK WORK.
        RETURN.
      ENDIF.
      result-created_sids = lines( without_sid ).
    ENDIF.
    IF usable-attribute_table IS NOT INITIAL.
      " every value with a SID, also one loaded outside the interval
      result-attribute_rows = write_attributes( characteristic = usable
                                                values         = sid_values( usable )
                                                calendar       = interval-calendar ).
    ENDIF.
    IF usable-text_table IS NOT INITIAL.
      " every value with a SID and the initial value (Not assigned)
      DATA(text_rows) = sid_values( usable ).
      INSERT initial_value( usable ) INTO TABLE text_rows.
      result-text_rows = write_texts( characteristic = usable values = text_rows ).
    ENDIF.
    " new members of the time dimensions: the kept Discover answers (MDSCHEMA_MEMBERS, cardinalities) are old
    zzxxmla1_cl_discover_cache=>clear( ).
    COMMIT WORK.
  ENDMETHOD.

  METHOD create_sids.
    " the SID conversion's table types, by name: RRSI_TH_VALSID (hashed, key VALUE) of RRSI_S_VALSID (VALUE, SID)
    DATA valsids TYPE REF TO data.
    DATA line TYPE REF TO data.
    FIELD-SYMBOLS <valsids> TYPE ANY TABLE.
    CREATE DATA valsids TYPE ('RRSI_TH_VALSID').
    ASSIGN valsids->* TO <valsids>.
    CREATE DATA line TYPE ('RRSI_S_VALSID').
    ASSIGN line->* TO FIELD-SYMBOL(<line>).
    ASSIGN COMPONENT 'VALUE' OF STRUCTURE <line> TO FIELD-SYMBOL(<value>).
    LOOP AT values INTO DATA(value).
      " a fiscal value is the variant in its two characters and the key, as BW's compounded value
      IF characteristic-compounding IS INITIAL.
        <value> = condense( value ).
      ELSE.
        <value> = value.
      ENDIF.
      INSERT <line> INTO TABLE <valsids>.
    ENDLOOP.
    DATA iobjnm TYPE c LENGTH 30.
    iobjnm = characteristic-name.
    " checked values (CHCKFL) for a characteristic with master data, as CL_RS_TIME_SERVICE makes them
    DATA(checked) = COND abap_bool( WHEN characteristic-attribute_table IS NOT INITIAL THEN abap_true ).
    DATA subrc TYPE sy-subrc.
    CALL FUNCTION 'RRSI_VAL_SID_CONVERT'
      EXPORTING
        i_iobjnm            = iobjnm
        i_th_valsid         = <valsids>
        i_checkfl           = checked
      IMPORTING
        e_subrc             = subrc
      EXCEPTIONS
        x_message           = 1
        chavl_not_allowed   = 2
        chavl_not_figure    = 3
        chavl_not_plausible = 4
        no_sid              = 5
        interval_not_found  = 6
        foreign_lock        = 7
        inherited_error     = 8
        OTHERS              = 9.
    IF sy-subrc <> 0.
      DATA message TYPE string.
      IF sy-msgid IS NOT INITIAL.
        MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 INTO message.
      ENDIF.
      result = |BW made no SIDs for { characteristic-name } (RRSI_VAL_SID_CONVERT { sy-subrc }): { message }|.
    ELSEIF subrc <> 0.
      result = |BW made no SIDs for { characteristic-name } (RRSI_VAL_SID_CONVERT, return code { subrc })|.
    ENDIF.
  ENDMETHOD.

  METHOD write_attributes.
    DATA rows TYPE REF TO data.
    DATA line TYPE REF TO data.
    FIELD-SYMBOLS <rows> TYPE STANDARD TABLE.
    CREATE DATA rows TYPE STANDARD TABLE OF (characteristic-attribute_table).
    ASSIGN rows->* TO <rows>.
    CREATE DATA line TYPE (characteristic-attribute_table).
    ASSIGN line->* TO FIELD-SYMBOL(<line>).
    LOOP AT values INTO DATA(value).
      DATA(period) = period( name = characteristic-name value = value ).
      IF period-known = abap_false.
        CONTINUE.
      ENDIF.
      CLEAR <line>.
      set_key( EXPORTING characteristic = characteristic value = value CHANGING line = <line> ).
      ASSIGN COMPONENT 'OBJVERS' OF STRUCTURE <line> TO FIELD-SYMBOL(<field>).
      <field> = 'A'.
      " a special period has no days of its own: no dates, no days
      IF period-from IS NOT INITIAL.
        ASSIGN COMPONENT 'DATEFROM' OF STRUCTURE <line> TO <field>.
        IF sy-subrc = 0.
          <field> = period-from.
        ENDIF.
        ASSIGN COMPONENT 'DATETO' OF STRUCTURE <line> TO <field>.
        IF sy-subrc = 0.
          <field> = period-to.
        ENDIF.
        ASSIGN COMPONENT 'NUMDAY' OF STRUCTURE <line> TO <field>.
        IF sy-subrc = 0.
          <field> = period-to - period-from + 1.
        ENDIF.
        ASSIGN COMPONENT 'NUMWDAY' OF STRUCTURE <line> TO <field>.
        IF sy-subrc = 0.
          <field> = nmax( val1 = 0 val2 = working_days( from = period-from to = period-to calendar = calendar ) ).
        ENDIF.
      ENDIF.
      " the year, month and quarter attributes only where the characteristic has them (0CALMONTH, 0CALQUARTER,
      " 0FISCPER)
      ASSIGN COMPONENT 'CALYEAR' OF STRUCTURE <line> TO <field>.
      IF sy-subrc = 0 AND characteristic-key_field <> `CALYEAR`.
        <field> = period-year.
      ENDIF.
      ASSIGN COMPONENT 'FISCYEAR' OF STRUCTURE <line> TO <field>.
      IF sy-subrc = 0 AND characteristic-key_field <> `FISCYEAR`.
        <field> = period-year.
      ENDIF.
      ASSIGN COMPONENT 'FISCPER3' OF STRUCTURE <line> TO <field>.
      IF sy-subrc = 0.
        <field> = period-fiscper3.
      ENDIF.
      ASSIGN COMPONENT 'CALMONTH2' OF STRUCTURE <line> TO <field>.
      IF sy-subrc = 0.
        <field> = period-month2.
      ENDIF.
      ASSIGN COMPONENT 'CALQUART1' OF STRUCTURE <line> TO <field>.
      IF sy-subrc = 0.
        <field> = period-quarter1.
      ENDIF.
      APPEND <line> TO <rows>.
    ENDLOOP.
    IF <rows> IS NOT INITIAL.
      MODIFY (characteristic-attribute_table) FROM TABLE <rows>.
      result = lines( <rows> ).
    ENDIF.
  ENDMETHOD.

  METHOD write_texts.
    DATA rows TYPE REF TO data.
    DATA line TYPE REF TO data.
    FIELD-SYMBOLS <rows> TYPE STANDARD TABLE.
    CREATE DATA rows TYPE STANDARD TABLE OF (characteristic-text_table).
    ASSIGN rows->* TO <rows>.
    CREATE DATA line TYPE (characteristic-text_table).
    ASSIGN line->* TO FIELD-SYMBOL(<line>).
    DATA(names) = labels( ).
    LOOP AT values INTO DATA(value).
      DATA(value_texts) = texts( name = characteristic-name value = value labels = names ).
      IF value_texts-known = abap_false.
        CONTINUE.
      ENDIF.
      CLEAR <line>.
      set_key( EXPORTING characteristic = characteristic value = value CHANGING line = <line> ).
      ASSIGN COMPONENT 'LANGU' OF STRUCTURE <line> TO FIELD-SYMBOL(<field>).
      <field> = c_language.
      " the text fields the characteristic has (0CALMONTH medium and long, 0CALQUARTER short and long, ...)
      ASSIGN COMPONENT 'TXTSH' OF STRUCTURE <line> TO <field>.
      IF sy-subrc = 0.
        <field> = value_texts-short.
      ENDIF.
      ASSIGN COMPONENT 'TXTMD' OF STRUCTURE <line> TO <field>.
      IF sy-subrc = 0.
        <field> = value_texts-medium.
      ENDIF.
      ASSIGN COMPONENT 'TXTLG' OF STRUCTURE <line> TO <field>.
      IF sy-subrc = 0.
        <field> = value_texts-long.
      ENDIF.
      APPEND <line> TO <rows>.
    ENDLOOP.
    IF <rows> IS NOT INITIAL.
      MODIFY (characteristic-text_table) FROM TABLE <rows>.
      result = lines( <rows> ).
    ENDIF.
  ENDMETHOD.

  METHOD set_key.
    ASSIGN COMPONENT characteristic-key_field OF STRUCTURE line TO FIELD-SYMBOL(<field>).
    IF characteristic-compounding IS INITIAL.
      <field> = value.
    ELSE.
      <field> = value+2.
      ASSIGN COMPONENT characteristic-compounding OF STRUCTURE line TO <field>.
      <field> = value(2).
    ENDIF.
  ENDMETHOD.

  METHOD text_values.
    DATA(where) = |LANGU = '{ c_language }' AND { characteristic-key_field } <> | &&
                  |'{ repeat( val = `0` occ = characteristic-length ) }'|.
    IF characteristic-compounding IS INITIAL.
      SELECT (characteristic-key_field)
        FROM (characteristic-text_table)
        WHERE (where)
        INTO TABLE @result.
      RETURN.
    ENDIF.
    DATA rows TYPE ty_t_compound.
    DATA(fields) = |{ characteristic-compounding }, { characteristic-key_field }|.
    SELECT (fields)
      FROM (characteristic-text_table)
      WHERE (where)
      INTO TABLE @rows.
    LOOP AT rows INTO DATA(row).
      INSERT compound_value( row ) INTO TABLE result.
    ENDLOOP.
  ENDMETHOD.

  METHOD labels.
    IF label_buffer IS INITIAL.
      SELECT mnr, ktx, ltx
        FROM t247
        WHERE spras = @c_language
        INTO TABLE @DATA(months).
      LOOP AT months INTO DATA(month).
        INSERT VALUE #( number = month-mnr short = condense( CONV string( month-ktx ) )
                        long = condense( CONV string( month-ltx ) ) ) INTO TABLE label_buffer-months.
      ENDLOOP.
      SELECT wotnr, kurzt, langt
        FROM t246
        WHERE sprsl = @c_language
        INTO TABLE @DATA(days).
      LOOP AT days INTO DATA(day).
        INSERT VALUE #( number = CONV i( day-wotnr ) short = condense( CONV string( day-kurzt ) )
                        long = condense( CONV string( day-langt ) ) ) INTO TABLE label_buffer-weekdays.
      ENDLOOP.
      " the texts BW's readers take from the text pools, with their English texts if a pool has none
      DATA pool TYPE textpool_table.
      READ TEXTPOOL 'SAPLRRSV' INTO pool LANGUAGE c_language.
      " the widths of the fields CL_RSMD_RS_0CALQUART1 reads them into: Q01 is Q padded to 10 places and a
      " translator's note
      label_buffer-quarter_short = text_symbol( pool = pool key = 'Q01' width = 10 default = `Q` ).
      label_buffer-quarter_long = text_symbol( pool = pool key = 'Q02' width = 20 default = `Quarter` ).
      READ TEXTPOOL 'SAPLRSDM' INTO pool LANGUAGE c_language.
      label_buffer-not_assigned = text_symbol( pool = pool key = '001' width = 60 default = `Not assigned` ).
    ENDIF.
    result = label_buffer.
  ENDMETHOD.

  METHOD text_symbol.
    READ TABLE pool INTO DATA(entry) WITH KEY id = 'I' key = key.
    IF sy-subrc <> 0 OR entry-entry IS INITIAL.
      result = default.
      RETURN.
    ENDIF.
    result = entry-entry.
    IF width < strlen( result ).
      result = result(width).
    ENDIF.
    result = condense( result ).
  ENDMETHOD.

  METHOD texts.
    DATA(text) = condense( CONV string( value ) ).
    IF text CO '0'.
      result = VALUE #( known  = abap_true
                        short  = labels-not_assigned
                        medium = labels-not_assigned
                        long   = labels-not_assigned ).
      RETURN.
    ENDIF.
    IF name = `0FISCYEAR`.
      " K4 only, as the attributes: its fiscal year is the calendar year
      IF strlen( text ) <> 6 OR text(2) <> c_fiscal_variant OR text+2 CN '0123456789'.
        RETURN.
      ENDIF.
      DATA(year) = substring( val = text off = 2 ).
      result = VALUE #( known = abap_true short = year medium = year long = |Fiscal year { year }| ).
      RETURN.
    ENDIF.
    IF text CN '0123456789'.
      RETURN.
    ENDIF.
    DATA(length) = strlen( text ).
    DATA number TYPE i.
    DATA month TYPE ty_name.
    CASE name.
      WHEN `0CALMONTH`.
        " CL_RSMD_RS_0CALMONTH: JAN 1997, January 1997
        IF length <> 6 OR CONV i( text(4) ) < 1000.
          RETURN.
        ENDIF.
        number = text+4(2).
        IF number < 1 OR number > 12.
          RETURN.
        ENDIF.
        month = VALUE #( labels-months[ number = number ] DEFAULT VALUE #( short = text+4(2) long = text+4(2) ) ).
        result = VALUE #( known  = abap_true
                          short  = |{ month-short } { text(4) }|
                          medium = |{ month-short } { text(4) }|
                          long   = |{ month-long } { text(4) }| ).
      WHEN `0CALMONTH2`.
        " CL_RSMD_RS_0CALMONTH2: JAN, January
        IF length <> 2.
          RETURN.
        ENDIF.
        number = text.
        IF number < 1 OR number > 12.
          RETURN.
        ENDIF.
        month = VALUE #( labels-months[ number = number ] DEFAULT VALUE #( short = text long = text ) ).
        result = VALUE #( known = abap_true short = month-short medium = month-short long = month-long ).
      WHEN `0CALQUARTER`.
        " as 0CALQUART1 with the year: Q1 1997, Quarter 1 1997
        IF length <> 5 OR CONV i( text(4) ) < 1000 OR text+4(1) NA '1234'.
          RETURN.
        ENDIF.
        result = VALUE #( known  = abap_true
                          short  = |{ labels-quarter_short }{ text+4(1) } { text(4) }|
                          medium = |{ labels-quarter_short }{ text+4(1) } { text(4) }|
                          long   = |{ labels-quarter_long } { text+4(1) } { text(4) }| ).
      WHEN `0CALQUART1`.
        " CL_RSMD_RS_0CALQUART1: Q1, Quarter 1
        IF length <> 1 OR text NA '1234'.
          RETURN.
        ENDIF.
        result = VALUE #( known  = abap_true
                          short  = |{ labels-quarter_short }{ text }|
                          medium = |{ labels-quarter_short }{ text }|
                          long   = |{ labels-quarter_long } { text }| ).
      WHEN `0WEEKDAY1`.
        " CL_RSMD_RS_0WEEKDAY1: MO, Monday
        IF length <> 1 OR text NA '1234567'.
          RETURN.
        ENDIF.
        number = text.
        DATA(day) = VALUE ty_name( labels-weekdays[ number = number ] DEFAULT VALUE #( short = text long = text ) ).
        result = VALUE #( known = abap_true short = day-short medium = day-long long = day-long ).
    ENDCASE.
  ENDMETHOD.

  METHOD initial_value.
    result = repeat( val = `0` occ = characteristic-length ).
    IF characteristic-compounding IS NOT INITIAL.
      " the variant's two characters blank
      result = |  { result }|.
    ENDIF.
  ENDMETHOD.

  METHOD missing_tables.
    DATA(tables) = VALUE string_table( ( characteristic-sid_table ) ).
    IF characteristic-attribute_table IS NOT INITIAL.
      APPEND characteristic-attribute_table TO tables.
    ENDIF.
    IF characteristic-text_table IS NOT INITIAL.
      APPEND characteristic-text_table TO tables.
    ENDIF.
    LOOP AT tables INTO DATA(table).
      SELECT SINGLE tabname
        FROM dd02l
        WHERE tabname = @table
          AND as4local = 'A'
          AND tabclass = 'TRANSP'
        INTO @DATA(found).
      IF sy-subrc <> 0.
        APPEND table TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD sid_values.
    DATA(where) = `SID <> 0`.
    IF characteristic-compounding IS INITIAL.
      SELECT (characteristic-key_field)
        FROM (characteristic-sid_table)
        WHERE (where)
        INTO TABLE @result.
      RETURN.
    ENDIF.
    DATA rows TYPE ty_t_compound.
    DATA(fields) = |{ characteristic-compounding }, { characteristic-key_field }|.
    SELECT (fields)
      FROM (characteristic-sid_table)
      WHERE (where)
      INTO TABLE @rows.
    LOOP AT rows INTO DATA(row).
      INSERT compound_value( row ) INTO TABLE result.
    ENDLOOP.
  ENDMETHOD.

  METHOD attribute_values.
    DATA(where) = |OBJVERS = 'A' AND { characteristic-key_field } <> '{ repeat( val = `0` occ = characteristic-length ) }'|.
    IF characteristic-compounding IS INITIAL.
      SELECT (characteristic-key_field)
        FROM (characteristic-attribute_table)
        WHERE (where)
        INTO TABLE @result.
      RETURN.
    ENDIF.
    DATA rows TYPE ty_t_compound.
    DATA(fields) = |{ characteristic-compounding }, { characteristic-key_field }|.
    SELECT (fields)
      FROM (characteristic-attribute_table)
      WHERE (where)
      INTO TABLE @rows.
    LOOP AT rows INTO DATA(row).
      INSERT compound_value( row ) INTO TABLE result.
    ENDLOOP.
  ENDMETHOD.

  METHOD compound_value.
    result = row-compounding.
    result+2 = row-key.
  ENDMETHOD.

  METHOD display.
    result = COND #( WHEN characteristic-compounding IS INITIAL THEN condense( value )
                     ELSE |{ condense( CONV string( value(2) ) ) }/{ condense( CONV string( value+2 ) ) }| ).
  ENDMETHOD.

  METHOD values.
    DATA value TYPE ty_value.
    DATA(first_year) = CONV i( interval-from(4) ).
    DATA(last_year) = CONV i( interval-to(4) ).
    CASE name.
      WHEN `0CALYEAR` OR `0FISCYEAR`.
        DO last_year - first_year + 1 TIMES.
          value = |{ first_year + sy-index - 1 WIDTH = 4 ALIGN = RIGHT PAD = '0' }|.
          IF name = `0FISCYEAR`.
            value = |{ c_fiscal_variant }{ value }|.
          ENDIF.
          INSERT value INTO TABLE result.
        ENDDO.
      WHEN `0CALQUARTER` OR `0CALMONTH` OR `0FISCPER`.
        " the months from the first to the last, each as its month or quarter
        DATA(month) = first_year * 12 + CONV i( interval-from+4(2) ) - 1.
        DATA(last_month) = last_year * 12 + CONV i( interval-to+4(2) ) - 1.
        WHILE month <= last_month.
          DATA(year) = month DIV 12.
          DATA(month_of_year) = month MOD 12 + 1.
          value = SWITCH #( name
            WHEN `0CALMONTH`
            THEN |{ year WIDTH = 4 ALIGN = RIGHT PAD = '0' }{ month_of_year WIDTH = 2 ALIGN = RIGHT PAD = '0' }|
            WHEN `0FISCPER`
            THEN |{ c_fiscal_variant }{ year WIDTH = 4 ALIGN = RIGHT PAD = '0' }{ month_of_year WIDTH = 3 ALIGN = RIGHT PAD = '0' }|
            ELSE |{ year WIDTH = 4 ALIGN = RIGHT PAD = '0' }{ ( month_of_year + 2 ) DIV 3 }| ).
          INSERT value INTO TABLE result.
          month = month + 1.
        ENDWHILE.
      WHEN `0CALWEEK`.
        " a day of every week: from the interval's first day in steps of a week, and its last day
        DATA(day) = interval-from.
        WHILE day <= interval-to.
          value = iso_week( day ).
          INSERT value INTO TABLE result.
          day = day + 7.
        ENDWHILE.
        value = iso_week( interval-to ).
        INSERT value INTO TABLE result.
      WHEN `0HALFYEAR1` OR `0CALQUART1`.
        DO COND i( WHEN name = `0HALFYEAR1` THEN 2 ELSE 4 ) TIMES.
          value = |{ sy-index }|.
          INSERT value INTO TABLE result.
        ENDDO.
      WHEN `0CALMONTH2`.
        DO 12 TIMES.
          value = |{ sy-index WIDTH = 2 ALIGN = RIGHT PAD = '0' }|.
          INSERT value INTO TABLE result.
        ENDDO.
      WHEN `0WEEKDAY1`.
        DO 7 TIMES.
          value = |{ sy-index }|.
          INSERT value INTO TABLE result.
        ENDDO.
    ENDCASE.
  ENDMETHOD.

  METHOD period.
    DATA(text) = condense( CONV string( value ) ).
    IF name = `0FISCYEAR` OR name = `0FISCPER`.
      " K4: the fiscal year is the calendar year, the periods 001 to 012 are its months
      IF strlen( text ) < 2 OR text(2) <> c_fiscal_variant.
        RETURN.
      ENDIF.
      DATA(key) = substring( val = text off = 2 ).
      IF key CN '0123456789' OR strlen( key ) <> COND i( WHEN name = `0FISCYEAR` THEN 4 ELSE 7 ).
        RETURN.
      ENDIF.
      IF name = `0FISCYEAR`.
        result = period( name = `0CALYEAR` value = key ).
        RETURN.
      ENDIF.
      DATA(number) = CONV i( key+4(3) ).
      IF number > 16 OR CONV i( key(4) ) < 1000.
        RETURN.
      ENDIF.
      " period 000 and the special periods have no dates of their own
      IF number >= 1 AND number <= 12.
        result = period( name = `0CALMONTH` value = |{ key(4) }{ key+5(2) }| ).
      ENDIF.
      result-year = key(4).
      result-fiscper3 = key+4(3).
      result-known = abap_true.
      RETURN.
    ENDIF.
    IF text CN '0123456789' OR strlen( text ) < 4.
      RETURN.
    ENDIF.
    DATA(year) = CONV i( text(4) ).
    IF year < 1000.
      RETURN.
    ENDIF.
    CASE name.
      WHEN `0CALYEAR`.
        IF strlen( text ) <> 4.
          RETURN.
        ENDIF.
        result-from = |{ text }0101|.
        result-to = |{ text }1231|.
      WHEN `0CALQUARTER`.
        IF strlen( text ) <> 5 OR text+4(1) NA '1234'.
          RETURN.
        ENDIF.
        DATA(quarter) = CONV i( text+4(1) ).
        result-from = |{ text(4) }{ quarter * 3 - 2 WIDTH = 2 ALIGN = RIGHT PAD = '0' }01|.
        result-to = last_day_of_month( year = year month = quarter * 3 ).
        result-year = text(4).
        result-quarter1 = quarter.
      WHEN `0CALMONTH`.
        IF strlen( text ) <> 6.
          RETURN.
        ENDIF.
        DATA(month) = CONV i( text+4(2) ).
        IF month < 1 OR month > 12.
          RETURN.
        ENDIF.
        result-from = |{ text }01|.
        result-to = last_day_of_month( year = year month = month ).
        result-year = text(4).
        result-month2 = text+4(2).
      WHEN `0CALWEEK`.
        IF strlen( text ) <> 6.
          RETURN.
        ENDIF.
        DATA(week) = CONV i( text+4(2) ).
        " week 1 is the week of 4 January; a week number past the year's last week is no week
        DATA(january_4) = CONV d( |{ text(4) }0104| ).
        DATA(monday) = CONV d( january_4 - weekday( january_4 ) + 1 + ( week - 1 ) * 7 ).
        IF week < 1 OR iso_week( monday ) <> text.
          RETURN.
        ENDIF.
        result-from = monday.
        result-to = monday + 6.
    ENDCASE.
    result-known = xsdbool( result-from IS NOT INITIAL ).
  ENDMETHOD.

  METHOD iso_week.
    DATA(thursday) = CONV d( date - weekday( date ) + 4 ).
    DATA(january_1) = CONV d( |{ thursday(4) }0101| ).
    result = |{ thursday(4) }{ ( thursday - january_1 ) DIV 7 + 1 WIDTH = 2 ALIGN = RIGHT PAD = '0' }|.
  ENDMETHOD.

  METHOD weekday.
    " 1 January 1900 was a Monday
    result = ( date - CONV d( '19000101' ) ) MOD 7 + 1.
  ENDMETHOD.

  METHOD last_day_of_month.
    DATA(next) = COND d( WHEN month = 12
                         THEN |{ year + 1 WIDTH = 4 ALIGN = RIGHT PAD = '0' }0101|
                         ELSE |{ year WIDTH = 4 ALIGN = RIGHT PAD = '0' }{ month + 1 WIDTH = 2 ALIGN = RIGHT PAD = '0' }01| ).
    result = next - 1.
  ENDMETHOD.

  METHOD working_days.
    " factory dates count the working days: the first working day from the start, the last one up to the end
    DATA first TYPE p LENGTH 3 DECIMALS 0.
    DATA last TYPE p LENGTH 3 DECIMALS 0.
    CALL FUNCTION 'DATE_CONVERT_TO_FACTORYDATE'
      EXPORTING
        correct_option      = '+'
        date                = from
        factory_calendar_id = calendar
      IMPORTING
        factorydate         = first
      EXCEPTIONS
        OTHERS              = 1.
    IF sy-subrc <> 0.
      result = -1.
      RETURN.
    ENDIF.
    CALL FUNCTION 'DATE_CONVERT_TO_FACTORYDATE'
      EXPORTING
        correct_option      = '-'
        date                = to
        factory_calendar_id = calendar
      IMPORTING
        factorydate         = last
      EXCEPTIONS
        OTHERS              = 1.
    IF sy-subrc <> 0.
      result = -1.
      RETURN.
    ENDIF.
    result = nmax( val1 = 0 val2 = last - first + 1 ).
  ENDMETHOD.

ENDCLASS.
