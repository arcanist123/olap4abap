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
"! are written here. The fiscal characteristics (they depend on a fiscal year variant) and 0CALDAY are not filled.
CLASS zzxxmla1_cl_time_md DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
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
        key_field       TYPE string,
        length          TYPE i,       " of the key (NUMC)
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
        first              TYPE string,  " the smallest value with a SID
        last               TYPE string,  " the largest
      END OF ty_status,
      ty_t_status TYPE STANDARD TABLE OF ty_status WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_fill_result,
        name           TYPE string,
        created_sids   TYPE i,
        attribute_rows TYPE i,       " written (inserted or replaced)
        error          TYPE string,  " the characteristic was not (completely) filled
      END OF ty_fill_result,
      ty_t_fill_result TYPE STANDARD TABLE OF ty_fill_result WITH EMPTY KEY.

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

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES ty_value TYPE c LENGTH 10.
    TYPES ty_t_value TYPE SORTED TABLE OF ty_value WITH UNIQUE KEY table_line.
    TYPES:
      "! the attributes of a value: its period and what it belongs to
      BEGIN OF ty_period,
        from     TYPE d,
        to       TYPE d,
        year     TYPE n LENGTH 4,
        month2   TYPE n LENGTH 2,
        quarter1 TYPE n LENGTH 1,
      END OF ty_period.

    "! The values of a characteristic in the interval: every period that overlaps it; the values of a characteristic
    "! without year (0CALMONTH2, ...) all of them.
    CLASS-METHODS values
      IMPORTING !name         TYPE string
                !interval     TYPE ty_interval
      RETURNING VALUE(result) TYPE ty_t_value.
    "! The period of a value of 0CALYEAR, 0CALQUARTER, 0CALMONTH or 0CALWEEK; initial if the value is none.
    CLASS-METHODS period
      IMPORTING !name         TYPE string
                !value        TYPE csequence
      RETURNING VALUE(result) TYPE ty_period.
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
    "! The non-initial values of the SID table.
    METHODS sid_values
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
        key_field = `CALQUARTER` length = 5 )
      ( name = `0CALMONTH`   sid_table = `/BI0/SCALMONTH`   attribute_table = `/BI0/PCALMONTH`
        key_field = `CALMONTH`   length = 6 )
      ( name = `0CALWEEK`    sid_table = `/BI0/SCALWEEK`    attribute_table = `/BI0/PCALWEEK`
        key_field = `CALWEEK`    length = 6 )
      ( name = `0HALFYEAR1`  sid_table = `/BI0/SHALFYEAR1`  key_field = `HALFYEAR1` length = 1 )
      ( name = `0CALQUART1`  sid_table = `/BI0/SCALQUART1`  key_field = `CALQUART1` length = 1 )
      ( name = `0CALMONTH2`  sid_table = `/BI0/SCALMONTH2`  key_field = `CALMONTH2` length = 2 )
      ( name = `0WEEKDAY1`   sid_table = `/BI0/SWEEKDAY1`   key_field = `WEEKDAY1`  length = 1 ) ).
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
      DATA(expected) = values( name = characteristic-name interval = interval ).
      DATA(sids) = sid_values( characteristic ).
      DATA(entry) = VALUE ty_status( characteristic = characteristic
                                     sids           = lines( sids )
                                     expected       = lines( expected ) ).
      LOOP AT expected INTO DATA(value).
        IF NOT line_exists( sids[ table_line = value ] ).
          entry-missing_sids = entry-missing_sids + 1.
        ENDIF.
      ENDLOOP.
      IF sids IS NOT INITIAL.
        entry-first = condense( sids[ 1 ] ).
        entry-last = condense( sids[ lines( sids ) ] ).
      ENDIF.
      IF characteristic-attribute_table IS NOT INITIAL.
        DATA(attributes) = attribute_values( characteristic ).
        entry-attributes = lines( attributes ).
        DATA(wanted) = sids.
        " one by one: INSERT LINES OF a value already there would end the program
        LOOP AT expected INTO value.
          INSERT value INTO TABLE wanted.
        ENDLOOP.
        LOOP AT wanted INTO value.
          IF NOT line_exists( attributes[ table_line = value ] ).
            entry-missing_attributes = entry-missing_attributes + 1.
          ENDIF.
        ENDLOOP.
      ENDIF.
      APPEND entry TO result.
    ENDLOOP.
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
    DATA(sids) = sid_values( characteristic ).
    DATA missing TYPE ty_t_value.
    LOOP AT values( name = characteristic-name interval = interval ) INTO DATA(value).
      IF NOT line_exists( sids[ table_line = value ] ).
        INSERT value INTO TABLE missing.
      ENDIF.
    ENDLOOP.
    IF missing IS NOT INITIAL.
      result-error = create_sids( characteristic = characteristic values = missing ).
      IF result-error IS NOT INITIAL.
        ROLLBACK WORK.
        RETURN.
      ENDIF.
      result-created_sids = lines( missing ).
    ENDIF.
    IF characteristic-attribute_table IS NOT INITIAL.
      " every value with a SID, also one loaded outside the interval
      result-attribute_rows = write_attributes( characteristic = characteristic
                                                values         = sid_values( characteristic )
                                                calendar       = interval-calendar ).
    ENDIF.
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
      <value> = condense( value ).
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
      IF period-from IS INITIAL.
        CONTINUE.
      ENDIF.
      CLEAR <line>.
      ASSIGN COMPONENT characteristic-key_field OF STRUCTURE <line> TO FIELD-SYMBOL(<field>).
      <field> = value.
      ASSIGN COMPONENT 'OBJVERS' OF STRUCTURE <line> TO <field>.
      <field> = 'A'.
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
      " the year, month and quarter attributes only where the characteristic has them (0CALMONTH, 0CALQUARTER)
      ASSIGN COMPONENT 'CALYEAR' OF STRUCTURE <line> TO <field>.
      IF sy-subrc = 0 AND characteristic-key_field <> `CALYEAR`.
        <field> = period-year.
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

  METHOD sid_values.
    DATA(where) = `SID <> 0`.
    SELECT (characteristic-key_field)
      FROM (characteristic-sid_table)
      WHERE (where)
      INTO TABLE @result.
  ENDMETHOD.

  METHOD attribute_values.
    DATA(where) = |OBJVERS = 'A' AND { characteristic-key_field } <> '{ repeat( val = `0` occ = characteristic-length ) }'|.
    SELECT (characteristic-key_field)
      FROM (characteristic-attribute_table)
      WHERE (where)
      INTO TABLE @result.
  ENDMETHOD.

  METHOD values.
    DATA value TYPE ty_value.
    DATA(first_year) = CONV i( interval-from(4) ).
    DATA(last_year) = CONV i( interval-to(4) ).
    CASE name.
      WHEN `0CALYEAR`.
        DO last_year - first_year + 1 TIMES.
          value = |{ first_year + sy-index - 1 WIDTH = 4 ALIGN = RIGHT PAD = '0' }|.
          INSERT value INTO TABLE result.
        ENDDO.
      WHEN `0CALQUARTER` OR `0CALMONTH`.
        " the months from the first to the last, each as its month or quarter
        DATA(month) = first_year * 12 + CONV i( interval-from+4(2) ) - 1.
        DATA(last_month) = last_year * 12 + CONV i( interval-to+4(2) ) - 1.
        WHILE month <= last_month.
          DATA(year) = month DIV 12.
          DATA(month_of_year) = month MOD 12 + 1.
          value = COND #( WHEN name = `0CALMONTH`
                          THEN |{ year WIDTH = 4 ALIGN = RIGHT PAD = '0' }{ month_of_year WIDTH = 2 ALIGN = RIGHT PAD = '0' }|
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
