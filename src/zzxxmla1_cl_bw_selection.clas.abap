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
"! The selection a cube restricts a characteristic by (docs/bw-schema-design-guide.md, section 3.8): a BW range table,
"! rows of sign (I include, E exclude), option (EQ, NE, GT, GE, LT, LE, BT, NB, CP, NP), low and high. A value matches
"! when no I row or some I row matches it, and no E row does. Values are BW's internal ones, compared as text; CP and
"! NP take BW's pattern (* any string, + one character), written as LIKE. Each restricted characteristic has a mode:
"! filter the cube (its members and the facts) or restrict members (its members only, the facts probed).
"! A selection has one text per use, all written here so that equal selections are equal texts:
"! - the annotation on the cube, olap4abap.filter.C or olap4abap.members.C, its rows separated by ;, each
"!   SIGN OPTION 'low' or SIGN OPTION 'low' 'high' (BT, NB); olap4abap.fixed.C = v, as fixing wrote it, is filter
"!   the cube with I EQ v;
"! - the selection of a view in table ZZXXMLA1_VIEW (selection_text), canonical: characteristics sorted, rows sorted
"!   and without duplicates, C=v for a single I EQ row, else C= and the rows separated by commas; characteristics
"!   separated by ;. The mode is not part of it: a characteristic's view is the same in both modes.
"! A value cannot contain a quote, and a pattern no % or _ (the CDS views of 7.50 have no LIKE ... ESCAPE).
CLASS zzxxmla1_cl_bw_selection DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS:
      "! What a selection applies to: the cube (members and facts) or the characteristic's members only.
      BEGIN OF c_mode,
        filter  TYPE c LENGTH 1 VALUE 'F',
        members TYPE c LENGTH 1 VALUE 'M',
      END OF c_mode.
    CONSTANTS:
      "! The names of the cube's annotations, followed by the characteristic; fixed is the name fixing wrote.
      BEGIN OF c_annotation,
        filter  TYPE string VALUE `olap4abap.filter.`,
        members TYPE string VALUE `olap4abap.members.`,
        fixed   TYPE string VALUE `olap4abap.fixed.`,
      END OF c_annotation.
    TYPES:
      "! a row of a range table
      BEGIN OF ty_row,
        sign   TYPE c LENGTH 1,
        option TYPE c LENGTH 2,
        low    TYPE string,
        high   TYPE string,
      END OF ty_row,
      ty_t_row TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.
    TYPES:
      "! a characteristic a cube restricts: the mode and the rows
      BEGIN OF ty_characteristic,
        iobjnm TYPE rsiobjnm,
        mode   TYPE c LENGTH 1,
        rows   TYPE ty_t_row,
      END OF ty_characteristic,
      ty_t_characteristic TYPE SORTED TABLE OF ty_characteristic WITH UNIQUE KEY iobjnm.

    "! The rows of an annotation's text (I EQ 'K4';E CP '*013'), checked and canonical.
    CLASS-METHODS parse
      IMPORTING text          TYPE csequence
      RETURNING VALUE(result) TYPE ty_t_row
      RAISING   zzxxmla1_cx_bw_provider.
    "! The rows as an annotation's text, canonical.
    CLASS-METHODS rows_text
      IMPORTING !rows         TYPE ty_t_row
      RETURNING VALUE(result) TYPE string.
    "! The rows sorted by sign, option, low and high, without duplicates.
    CLASS-METHODS canonical
      IMPORTING !rows         TYPE ty_t_row
      RETURNING VALUE(result) TYPE ty_t_row.
    "! Refuses rows that are no range table this class can write: no row, an unknown sign or option, a quote in a
    "! value, a high value but for BT and NB or none or one below the low one there, a % or _ in a pattern.
    "! characteristic names the selection in the message.
    CLASS-METHODS check
      IMPORTING characteristic TYPE csequence
                !rows          TYPE ty_t_row
      RAISING   zzxxmla1_cx_bw_provider.
    "! The single row I EQ value.
    CLASS-METHODS equals
      IMPORTING !value        TYPE csequence
      RETURNING VALUE(result) TYPE ty_t_row.
    "! Whether the rows are one I EQ row: one value, which uncompounds a characteristic compounded with it.
    CLASS-METHODS is_single
      IMPORTING !rows         TYPE ty_t_row
      RETURNING VALUE(result) TYPE abap_bool.
    "! The value of a single I EQ row, initial for other rows.
    CLASS-METHODS single_value
      IMPORTING !rows         TYPE ty_t_row
      RETURNING VALUE(result) TYPE string.
    "! The selection of a view as table ZZXXMLA1_VIEW keys it (0FISCPER=E CP '*013',E CP '*014';0FISCVARNT=K4);
    "! initial for none.
    CLASS-METHODS selection_text
      IMPORTING selection     TYPE ty_t_characteristic
      RETURNING VALUE(result) TYPE string.
    "! The SQL condition of the rows on a column (an expression: s.FISCPER in a CDS view, "FISCPER" in native SQL),
    "! the same text for both: the I rows combined with OR, then each E row negated, all combined with AND; initial
    "! for no rows.
    CLASS-METHODS condition
      IMPORTING !rows         TYPE ty_t_row
                !column       TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! The annotation's name of a characteristic in a mode.
    CLASS-METHODS annotation_name
      IMPORTING characteristic TYPE csequence
                !mode          TYPE c
      RETURNING VALUE(result)  TYPE string.
    "! The characteristic, mode and rows of an annotation; initial if the name is none of a selection.
    CLASS-METHODS from_annotation
      IMPORTING !name         TYPE csequence
                !value        TYPE csequence
      RETURNING VALUE(result) TYPE ty_characteristic
      RAISING   zzxxmla1_cx_bw_provider.

  PROTECTED SECTION.
  PRIVATE SECTION.
    "! the options of a range table, each followed by its negation
    CONSTANTS c_options TYPE string VALUE `EQ NE NE EQ GT LE GE LT LT GE LE GT BT NB NB BT CP NP NP CP`.

    "! The text of a row: SIGN OPTION 'low', and 'high' for BT and NB.
    CLASS-METHODS row_text
      IMPORTING !row          TYPE ty_row
      RETURNING VALUE(result) TYPE string.
    "! The condition of one option on a column; CP and NP as LIKE.
    CLASS-METHODS option_condition
      IMPORTING !option       TYPE csequence
                low           TYPE string
                high          TYPE string
                !column       TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! The option that matches what an option does not.
    CLASS-METHODS negated
      IMPORTING !option       TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! Skips blanks from position.
    CLASS-METHODS skip_blanks
      IMPORTING text     TYPE string
      CHANGING  position TYPE i.
    "! The word of letters at position (I, EQ), upper case; position after it.
    CLASS-METHODS read_word
      IMPORTING text          TYPE string
      CHANGING  position      TYPE i
      RETURNING VALUE(result) TYPE string.
    "! The value in quotes at position; position after the closing quote. Refused if there is no closing quote.
    CLASS-METHODS read_value
      IMPORTING text          TYPE string
      CHANGING  position      TYPE i
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_bw_provider.
    CLASS-METHODS fail
      IMPORTING !text TYPE string
      RAISING   zzxxmla1_cx_bw_provider.
ENDCLASS.



CLASS zzxxmla1_cl_bw_selection IMPLEMENTATION.

  METHOD parse.
    DATA(source) = CONV string( text ).
    DATA(length) = strlen( source ).
    DATA(position) = 0.
    DO.
      skip_blanks( EXPORTING text = source CHANGING position = position ).
      DATA(row) = VALUE ty_row( ).
      row-sign = read_word( EXPORTING text = source CHANGING position = position ).
      skip_blanks( EXPORTING text = source CHANGING position = position ).
      row-option = read_word( EXPORTING text = source CHANGING position = position ).
      skip_blanks( EXPORTING text = source CHANGING position = position ).
      row-low = read_value( EXPORTING text = source CHANGING position = position ).
      skip_blanks( EXPORTING text = source CHANGING position = position ).
      IF position < length AND source+position(1) = `'`.
        row-high = read_value( EXPORTING text = source CHANGING position = position ).
        skip_blanks( EXPORTING text = source CHANGING position = position ).
      ENDIF.
      INSERT row INTO TABLE result.
      IF position >= length.
        EXIT.
      ENDIF.
      IF source+position(1) <> `;`.
        fail( |The selection { source } has { substring( val = source off = position ) } where ; or the end | &&
              |is expected| ).
      ENDIF.
      position = position + 1.
    ENDDO.
    check( characteristic = `The selection` rows = result ).
    result = canonical( result ).
  ENDMETHOD.

  METHOD rows_text.
    LOOP AT canonical( rows ) INTO DATA(row).
      result = COND #( WHEN result IS INITIAL THEN row_text( row ) ELSE |{ result };{ row_text( row ) }| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD canonical.
    result = rows.
    SORT result BY sign option low high.
    DELETE ADJACENT DUPLICATES FROM result COMPARING sign option low high.
  ENDMETHOD.

  METHOD check.
    IF rows IS INITIAL.
      fail( |{ characteristic } has no row| ).
    ENDIF.
    LOOP AT rows INTO DATA(row).
      DATA(text) = row_text( row ).
      IF row-sign <> 'I' AND row-sign <> 'E'.
        fail( |{ characteristic }: { text } has the sign { row-sign }, not I or E| ).
      ENDIF.
      IF row-option IS INITIAL OR negated( row-option ) IS INITIAL.
        fail( |{ characteristic }: { text } has the option { row-option }, not one of EQ, NE, GT, GE, LT, LE, BT, | &&
              |NB, CP, NP| ).
      ENDIF.
      IF row-low CA `'` OR row-high CA `'`.
        fail( |{ characteristic }: a value cannot contain a quote| ).
      ENDIF.
      IF row-option = 'BT' OR row-option = 'NB'.
        IF row-high IS INITIAL.
          fail( |{ characteristic }: { text } needs a high value| ).
        ENDIF.
        IF row-high < row-low.
          fail( |{ characteristic }: { text } has a high value below the low one| ).
        ENDIF.
      ELSEIF row-high IS NOT INITIAL.
        fail( |{ characteristic }: { text } has a high value, which only BT and NB take| ).
      ENDIF.
      IF ( row-option = 'CP' OR row-option = 'NP' ) AND row-low CA `%_`.
        fail( |{ characteristic }: the pattern { row-low } cannot contain % or _| ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD equals.
    result = VALUE #( ( sign = 'I' option = 'EQ' low = value ) ).
  ENDMETHOD.

  METHOD is_single.
    result = xsdbool( lines( rows ) = 1 AND rows[ 1 ]-sign = 'I' AND rows[ 1 ]-option = 'EQ' ).
  ENDMETHOD.

  METHOD single_value.
    IF is_single( rows ) = abap_true.
      result = rows[ 1 ]-low.
    ENDIF.
  ENDMETHOD.

  METHOD selection_text.
    LOOP AT selection INTO DATA(characteristic).
      DATA(rows) = canonical( characteristic-rows ).
      DATA(text) = ``.
      IF is_single( rows ) = abap_true.
        text = rows[ 1 ]-low.
      ELSE.
        LOOP AT rows INTO DATA(row).
          text = COND #( WHEN text IS INITIAL THEN row_text( row ) ELSE |{ text },{ row_text( row ) }| ).
        ENDLOOP.
      ENDIF.
      text = |{ characteristic-iobjnm }={ text }|.
      result = COND #( WHEN result IS INITIAL THEN text ELSE |{ result };{ text }| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD condition.
    DATA(included) = ``.
    DATA(count) = 0.
    LOOP AT canonical( rows ) INTO DATA(row) WHERE sign = 'I'.
      DATA(part) = option_condition( option = row-option low = row-low high = row-high column = column ).
      included = COND #( WHEN included IS INITIAL THEN part ELSE |{ included } or { part }| ).
      count = count + 1.
    ENDLOOP.
    IF count > 1.
      included = |( { included } )|.
    ENDIF.
    result = included.
    LOOP AT canonical( rows ) INTO row WHERE sign = 'E'.
      part = option_condition( option = negated( row-option ) low = row-low high = row-high column = column ).
      result = COND #( WHEN result IS INITIAL THEN part ELSE |{ result } and { part }| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD annotation_name.
    result = COND #( WHEN mode = c_mode-members THEN c_annotation-members ELSE c_annotation-filter ) &&
             characteristic.
  ENDMETHOD.

  METHOD from_annotation.
    DATA(annotation) = CONV string( name ).
    DATA(length) = 0.
    IF strlen( annotation ) > strlen( c_annotation-filter ) AND
       substring( val = annotation len = strlen( c_annotation-filter ) ) = c_annotation-filter.
      result-mode = c_mode-filter.
      length = strlen( c_annotation-filter ).
    ELSEIF strlen( annotation ) > strlen( c_annotation-members ) AND
           substring( val = annotation len = strlen( c_annotation-members ) ) = c_annotation-members.
      result-mode = c_mode-members.
      length = strlen( c_annotation-members ).
    ELSEIF strlen( annotation ) > strlen( c_annotation-fixed ) AND
           substring( val = annotation len = strlen( c_annotation-fixed ) ) = c_annotation-fixed.
      result-iobjnm = substring( val = annotation off = strlen( c_annotation-fixed ) ).
      result-mode = c_mode-filter.
      result-rows = equals( value ).
      check( characteristic = result-iobjnm rows = result-rows ).
      RETURN.
    ELSE.
      RETURN.
    ENDIF.
    result-iobjnm = substring( val = annotation off = length ).
    TRY.
        result-rows = parse( value ).
      CATCH zzxxmla1_cx_bw_provider INTO DATA(error).
        fail( |Annotation { annotation }: { error->error_message }| ).
    ENDTRY.
  ENDMETHOD.

  METHOD row_text.
    result = |{ row-sign } { row-option } '{ row-low }'|.
    IF row-option = 'BT' OR row-option = 'NB'.
      result = |{ result } '{ row-high }'|.
    ENDIF.
  ENDMETHOD.

  METHOD option_condition.
    CASE option.
      WHEN 'EQ'.
        result = |{ column } = '{ low }'|.
      WHEN 'NE'.
        result = |{ column } <> '{ low }'|.
      WHEN 'GT'.
        result = |{ column } > '{ low }'|.
      WHEN 'GE'.
        result = |{ column } >= '{ low }'|.
      WHEN 'LT'.
        result = |{ column } < '{ low }'|.
      WHEN 'LE'.
        result = |{ column } <= '{ low }'|.
      WHEN 'BT'.
        result = |{ column } between '{ low }' and '{ high }'|.
      WHEN 'NB'.
        result = |{ column } not between '{ low }' and '{ high }'|.
      WHEN 'CP' OR 'NP'.
        DATA(pattern) = translate( val = low from = `*+` to = `%_` ).
        result = COND #( WHEN option = 'CP' THEN |{ column } like '{ pattern }'|
                         ELSE |{ column } not like '{ pattern }'| ).
    ENDCASE.
  ENDMETHOD.

  METHOD negated.
    SPLIT c_options AT ` ` INTO TABLE DATA(options).
    DATA(index) = 1.
    WHILE index < lines( options ).
      IF options[ index ] = option.
        result = options[ index + 1 ].
        RETURN.
      ENDIF.
      index = index + 2.
    ENDWHILE.
  ENDMETHOD.

  METHOD skip_blanks.
    DATA(length) = strlen( text ).
    WHILE position < length AND text+position(1) = ` `.
      position = position + 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD read_word.
    DATA(length) = strlen( text ).
    DATA(start) = position.
    WHILE position < length AND to_upper( text+position(1) ) CA sy-abcde.
      position = position + 1.
    ENDWHILE.
    result = to_upper( substring( val = text off = start len = position - start ) ).
  ENDMETHOD.

  METHOD read_value.
    DATA(length) = strlen( text ).
    IF position >= length OR text+position(1) <> `'`.
      fail( |The selection { text } has no value in quotes at { position + 1 }| ).
    ENDIF.
    DATA(start) = position + 1.
    FIND `'` IN SECTION OFFSET start OF text MATCH OFFSET DATA(close).
    IF sy-subrc <> 0.
      fail( |The selection { text } has a value without its closing quote| ).
    ENDIF.
    result = substring( val = text off = start len = close - start ).
    position = close + 1.
  ENDMETHOD.

  METHOD fail.
    RAISE EXCEPTION TYPE zzxxmla1_cx_bw_provider EXPORTING error_message = text.
  ENDMETHOD.

ENDCLASS.
