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
"! The metadata of a BW InfoProvider that a schema is proposed for (docs/schema-generator.md, Providers): a
"! HANA-optimised InfoCube (RSDCUBE type B, subtype F: flat) or a cube-type aDSO (RSOADSO: activate data, cube delta
"! only). Every name is BW's, never built: the fact table (RSD_FACTTAB_GET_FOR_CUBE, CL_RSO_ADSO=>GET_TABLNM, the
"! aDSO's reporting view), the fields (RSDIOBJ-FIELDNM; an InfoCube's characteristics are its SID columns,
"! RSD_SIDNM_GET_FROM_IOBJNM) and the characteristics' tables and views (ZZXXMLA1_CL_BW_VIEW_GEN, the view of the
"! basic characteristic). Each column comes with its DDIC type, a characteristic with its text and its attributes (with
"! their texts) as columns of its view, and for each attribute whether the provider switches it on as a navigation
"! attribute (docs/bw-schema-design-guide.md, section 3.2): an InfoCube lists it as CHARACTERISTIC__ATTRIBUTE in
"! RSDDIMEIOBJ, an aDSO switches on the navigation attributes of a characteristic together (navigational_attr_on).
"! What a schema cannot use is a note with the reason: units and currencies, fields without InfoObject, texts a view
"! cannot join. Nothing is changed.
"! A compounded characteristic has a name column, its compounding and its value (docs/bw-schema-design-guide.md,
"! section 3.7). An aDSO with one is read from its fact view (ZZXXMLA1_CL_BW_VIEW_GEN, a placeholder if it is not
"! generated yet): its fields without namespace, and the compounded characteristic's SID as its fact column.
"! Read for a cube that fixes characteristics (section 3.8, 0FISCVARNT = K4), the provider is read from its fact view
"! for them, an InfoCube too, a fixed characteristic from its view filtered on its value and a characteristic
"! compounded with fixed ones from its view for them: one whose compounding is all fixed has no name column (on an
"! aDSO it keeps its SID as fact column).
CLASS zzxxmla1_cl_bw_provider DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS:
      BEGIN OF c_kind,
        cube TYPE string VALUE `InfoCube`,
        adso TYPE string VALUE `aDSO`,
      END OF c_kind.
    TYPES:
      "! an InfoProvider a schema can be proposed for
      BEGIN OF ty_entry,
        name     TYPE string,
        kind     TYPE string,
        text     TYPE string,
        infoarea TYPE string,
      END OF ty_entry,
      ty_t_entry TYPE STANDARD TABLE OF ty_entry WITH EMPTY KEY.
    TYPES:
      "! something of the provider the schema does not use, and why
      BEGIN OF ty_note,
        iobjnm TYPE string,
        reason TYPE string,
      END OF ty_note,
      ty_t_note TYPE STANDARD TABLE OF ty_note WITH EMPTY KEY.
    TYPES:
      "! a column of a table or view: name and DDIC type
      BEGIN OF ty_column,
        name     TYPE string,
        datatype TYPE string,
        length   TYPE i,
        decimals TYPE i,
      END OF ty_column.
    TYPES:
      "! an attribute of a characteristic, time-independent or time-dependent (at the key date); its column is the one
      "! of the attribute table, which the characteristic's view delivers without namespace, its int column the view's
      "! number of a NUMC column (COLUMN_INT, initial for any other), its text column the view's column of its text,
      "! initial if it has none
      BEGIN OF ty_attribute,
        iobjnm      TYPE string,
        text        TYPE string,
        column      TYPE ty_column,
        int_column  TYPE ty_column,
        text_column TYPE string,
        navigation  TYPE abap_bool,  " a navigation attribute the provider switches on
      END OF ty_attribute,
      ty_t_attribute TYPE STANDARD TABLE OF ty_attribute WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_characteristic,
        iobjnm      TYPE string,
        text        TYPE string,
        iobjtp      TYPE string,     " CHA, or TIM for BW's time characteristics
        basic       TYPE string,     " whose tables and view it has: itself, or the one it references
        fact_column TYPE ty_column,  " InfoCube: the SID column; aDSO: the value
        has_sids    TYPE abap_bool,  " it has a SID table, so ZZXXMLA1_CL_BW_VIEW_GEN can generate its view
        view        TYPE string,     " the database view of the basic characteristic's DDL source, initial if it is
                                     " not generated yet or lacks a column it is generated with now
        key_column  TYPE ty_column,  " the characteristic's value as a column of the view
        "! NUMC: the view's number of the key column (ZFMSTORE_INT); initial for any other
        key_int_column TYPE ty_column,
        "! compounded: the view's column of the compounding and the value (K4/2024001), initial for any other
        name_column TYPE ty_column,
        "! the fact column is the SID: always on an InfoCube, on an aDSO for a compounded characteristic (its fact view's)
        fact_sid    TYPE abap_bool,
        text_column TYPE string,     " the column of its text, initial if it has none
        attributes  TYPE ty_t_attribute,
        "! the characteristics its basic one is compounded with, in BW's order (a cube fixes them with it)
        compounding TYPE string_table,
      END OF ty_characteristic,
      ty_t_characteristic TYPE STANDARD TABLE OF ty_characteristic WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_key_figure,
        iobjnm                TYPE string,
        text                  TYPE string,
        fact_column           TYPE ty_column,
        aggregation           TYPE string,     " SUM, MIN or MAX (RSDAGGRGEN; the aDSO's own for an aDSO)
        exception_aggregation TYPE string,     " RSDAGGREXC; equal to the aggregation if there is none
        non_cumulative        TYPE abap_bool,
      END OF ty_key_figure,
      ty_t_key_figure TYPE STANDARD TABLE OF ty_key_figure WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_provider,
        name            TYPE string,
        kind            TYPE string,
        text            TYPE string,
        infoarea        TYPE string,
        fact_table      TYPE string,
        "! the characteristics fixed to a value; they are in characteristics too
        fixed           TYPE zzxxmla1_cl_bw_view_gen=>ty_t_fixed,
        characteristics TYPE ty_t_characteristic,  " in the order of the provider
        key_figures     TYPE ty_t_key_figure,
        notes           TYPE ty_t_note,
      END OF ty_provider.

    "! The HANA-optimised InfoCubes and cube-type aDSOs, by name.
    METHODS providers
      RETURNING VALUE(result) TYPE ty_t_entry.
    "! The metadata of an InfoCube or aDSO, for a cube that fixes the given characteristics.
    METHODS read
      IMPORTING name          TYPE csequence
                fixed         TYPE zzxxmla1_cl_bw_view_gen=>ty_t_fixed OPTIONAL
      RETURNING VALUE(result) TYPE ty_provider
      RAISING   zzxxmla1_cx_bw_provider.
    "! Refuses the fixed characteristics of a provider read with them: each must be a characteristic of the provider,
    "! fixed together with its compounding, to a value that has a SID and no quote, and not referenced by another
    "! characteristic of the provider (which shares its view); the selection fits table ZZXXMLA1_VIEW
    "! (c_selection_length of the view generator).
    METHODS check_fixed
      IMPORTING provider TYPE ty_provider
      RAISING   zzxxmla1_cx_bw_provider.
    "! The InfoCube or aDSO whose fact table or reporting view the table is, initial if there is none. BW names them
    "! after the provider (/BIC/FZCLVISIT, /BIC/AZCLVISITA7), so only the providers whose name is in the table's are
    "! asked.
    METHODS provider_of_fact_table
      IMPORTING table         TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! The values a characteristic can be fixed to (its SID table without the initial value), sorted, at most
    "! max_values + 1 (more than max_values: there are more); its compounding must be fixed.
    METHODS values
      IMPORTING characteristic TYPE csequence
                fixed          TYPE zzxxmla1_cl_bw_view_gen=>ty_t_fixed OPTIONAL
                max_values     TYPE i DEFAULT 500
      RETURNING VALUE(result)  TYPE string_table
      RAISING   zzxxmla1_cx_bw_provider.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES ty_t_column TYPE HASHED TABLE OF ty_column WITH UNIQUE KEY name.

    DATA views TYPE REF TO zzxxmla1_cl_bw_view_gen.
    "! the characteristics the provider is read for as fixed
    DATA fixed TYPE zzxxmla1_cl_bw_view_gen=>ty_t_fixed.
    "! the notes of the attributes, collected while the characteristics are read
    DATA notes TYPE ty_t_note.
    "! an InfoCube's navigation attributes, CHARACTERISTIC__ATTRIBUTE
    DATA cube_navigation TYPE STANDARD TABLE OF rsiobjnm WITH EMPTY KEY.

    "! An InfoCube's fact table, initial if BW gives none.
    METHODS cube_fact_table
      IMPORTING cube          TYPE rsinfocube
      RETURNING VALUE(result) TYPE string.
    "! An aDSO's reporting view, initial if BW gives none.
    METHODS adso_reporting_view
      IMPORTING adso          TYPE rsoadsonm
      RETURNING VALUE(result) TYPE string.
    METHODS read_cube
      IMPORTING cube     TYPE rsinfocube
      CHANGING  provider TYPE ty_provider
      RAISING   zzxxmla1_cx_bw_provider.
    METHODS read_adso
      IMPORTING adso     TYPE rsoadsonm
      CHANGING  provider TYPE ty_provider
      RAISING   zzxxmla1_cx_bw_provider.
    "! The provider's fact view for the fixed characteristics if it has every column of the layout, else its
    "! placeholder.
    METHODS fact_view
      IMPORTING provider      TYPE rsinfoprov
                layout        TYPE zzxxmla1_cl_bw_view_gen=>ty_fact_layout
      RETURNING VALUE(result) TYPE string.
    "! A characteristic with its view and attributes; adso_navigation: an aDSO switches on its navigation attributes.
    METHODS characteristic
      IMPORTING iobjnm          TYPE rsiobjnm
                iobjtp          TYPE rsiobjtp
                fact_column     TYPE ty_column
                adso_navigation TYPE abap_bool OPTIONAL
      RETURNING VALUE(result)   TYPE ty_characteristic.
    "! The view's number of a NUMC column, initial if it has none.
    CLASS-METHODS int_column
      IMPORTING layout        TYPE zzxxmla1_cl_bw_view_gen=>ty_layout
                column        TYPE string
      RETURNING VALUE(result) TYPE ty_column.
    "! A key figure with its aggregation; aggregation is the aDSO's, initial for the InfoObject's.
    METHODS key_figure
      IMPORTING iobjnm        TYPE rsiobjnm
                fact_column   TYPE ty_column
                aggregation   TYPE rsdaggrgen OPTIONAL
      RETURNING VALUE(result) TYPE ty_key_figure.
    "! The columns of a table or view (DD03L).
    METHODS columns_of
      IMPORTING table         TYPE csequence
      RETURNING VALUE(result) TYPE ty_t_column.
    "! The long text of an InfoObject in the logon language, else the short one, else its name.
    METHODS text_of
      IMPORTING iobjnm        TYPE rsiobjnm
      RETURNING VALUE(result) TYPE string.
    "! The condition on a characteristic's SID table for its compounding fixed to the given values (initial: none),
    "! refused if one of its compounding is not fixed or a value has a quote.
    METHODS compounding_condition
      IMPORTING tables         TYPE zzxxmla1_cl_bw_view_gen=>ty_tables
                characteristic TYPE csequence
                fixed          TYPE zzxxmla1_cl_bw_view_gen=>ty_t_fixed
      RETURNING VALUE(result)  TYPE string
      RAISING   zzxxmla1_cx_bw_provider.
    METHODS fail
      IMPORTING text TYPE string
      RAISING   zzxxmla1_cx_bw_provider.
ENDCLASS.



CLASS zzxxmla1_cl_bw_provider IMPLEMENTATION.

  METHOD providers.
    SELECT c~infocube, c~infoarea, t~txtlg FROM rsdcube AS c
      LEFT OUTER JOIN rsdcubet AS t ON t~infocube = c~infocube AND t~objvers = c~objvers AND t~langu = @sy-langu
      WHERE c~objvers = 'A' AND c~cubetype = 'B' AND c~cubesubtype = 'F'
      INTO TABLE @DATA(cubes).
    LOOP AT cubes INTO DATA(cube).
      APPEND VALUE #( name = cube-infocube kind = c_kind-cube text = cube-txtlg infoarea = cube-infoarea ) TO result.
    ENDLOOP.
    " the aDSO's own text is the one of type EUSR without column
    SELECT a~adsonm, a~infoarea, t~description FROM rsoadso AS a
      LEFT OUTER JOIN rsoadsot AS t ON t~adsonm = a~adsonm AND t~objvers = a~objvers AND t~langu = @sy-langu
                                   AND t~ttyp = 'EUSR' AND t~colname = @space
      WHERE a~objvers = 'A' AND a~activate_data = 'X' AND a~cubedeltaonly = 'X'
      INTO TABLE @DATA(adsos).
    LOOP AT adsos INTO DATA(adso).
      APPEND VALUE #( name = adso-adsonm kind = c_kind-adso text = adso-description infoarea = adso-infoarea )
        TO result.
    ENDLOOP.
    SORT result BY name.
  ENDMETHOD.

  METHOD read.
    views = NEW #( ).
    CLEAR: notes, cube_navigation.
    me->fixed = fixed.
    DATA(upper) = to_upper( name ).
    DATA cube TYPE rsinfocube.
    DATA adso TYPE rsoadsonm.
    cube = upper.
    adso = upper.
    SELECT SINGLE c~infocube, c~infoarea, t~txtlg FROM rsdcube AS c
      LEFT OUTER JOIN rsdcubet AS t ON t~infocube = c~infocube AND t~objvers = c~objvers AND t~langu = @sy-langu
      WHERE c~infocube = @cube AND c~objvers = 'A' AND c~cubetype = 'B' AND c~cubesubtype = 'F'
      INTO @DATA(cube_row).
    IF sy-subrc = 0.
      result = VALUE #( name = cube kind = c_kind-cube text = cube_row-txtlg infoarea = cube_row-infoarea ).
      read_cube( EXPORTING cube = cube CHANGING provider = result ).
    ELSE.
      SELECT SINGLE adsonm FROM rsoadso
        WHERE adsonm = @adso AND objvers = 'A' AND activate_data = 'X' AND cubedeltaonly = 'X'
        INTO @DATA(found).
      IF sy-subrc <> 0.
        fail( |{ upper } is neither an active HANA-optimised InfoCube nor an active cube-type aDSO| ).
      ENDIF.
      result = VALUE #( name = found kind = c_kind-adso ).
      read_adso( EXPORTING adso = adso CHANGING provider = result ).
    ENDIF.
    result-fixed = fixed.
    APPEND LINES OF notes TO result-notes.
  ENDMETHOD.

  METHOD check_fixed.
    IF strlen( zzxxmla1_cl_bw_view_gen=>selection_text( provider-fixed ) ) > zzxxmla1_cl_bw_view_gen=>c_selection_length.
      fail( |The fixed characteristics are longer than { zzxxmla1_cl_bw_view_gen=>c_selection_length
            } characters together| ).
    ENDIF.
    IF views IS NOT BOUND.
      views = NEW #( ).
    ENDIF.
    LOOP AT provider-fixed INTO DATA(value).
      IF NOT line_exists( provider-characteristics[ iobjnm = CONV string( value-iobjnm ) ] ).
        fail( |{ value-iobjnm } is not a characteristic of { provider-name }| ).
      ENDIF.
      IF value-value CA `'`.
        fail( |{ value-iobjnm }: a fixed value cannot contain a quote| ).
      ENDIF.
      " its view is filtered on its value, so no other characteristic may share it
      LOOP AT provider-characteristics INTO DATA(referencing) WHERE basic = value-iobjnm AND iobjnm <> value-iobjnm.
        fail( |{ value-iobjnm } cannot be fixed: { referencing-iobjnm } references it and shares its view| ).
      ENDLOOP.
      " its compounding fixed too, and a SID for all its key fields
      DATA(tables) = views->tables( value-iobjnm ).
      IF tables-sids IS INITIAL.
        fail( |{ value-iobjnm } has no SID table| ).
      ENDIF.
      DATA(conditions) = |{ tables-key_field } = '{ value-value }'|.
      DATA(compounding) = compounding_condition( tables = tables characteristic = value-iobjnm
                                                 fixed = provider-fixed ).
      IF compounding IS NOT INITIAL.
        conditions = |{ conditions } AND { compounding }|.
      ENDIF.
      SELECT COUNT(*) FROM (tables-sids) WHERE (conditions).
      IF sy-dbcnt = 0.
        fail( |{ value-iobjnm } has no value { value-value }| ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD values.
    IF views IS NOT BOUND.
      views = NEW #( ).
    ENDIF.
    DATA(tables) = views->tables( CONV #( to_upper( characteristic ) ) ).
    IF tables-sids IS INITIAL.
      fail( |{ to_upper( characteristic ) } is no characteristic with a SID table| ).
    ENDIF.
    " BW's initial value has SID 0
    DATA(conditions) = |SID > 0|.
    DATA(compounding) = compounding_condition( tables = tables characteristic = to_upper( characteristic )
                                               fixed = fixed ).
    IF compounding IS NOT INITIAL.
      conditions = |{ conditions } AND { compounding }|.
    ENDIF.
    DATA rows TYPE STANDARD TABLE OF rsd_chavl WITH EMPTY KEY.
    DATA(order_by) = |{ tables-key_field } ASCENDING|.
    DATA(limit) = max_values + 1.
    SELECT DISTINCT (tables-key_field) FROM (tables-sids)
      WHERE (conditions)
      ORDER BY (order_by)
      INTO TABLE @rows
      UP TO @limit ROWS.
    result = VALUE #( FOR row IN rows ( CONV string( row ) ) ).
  ENDMETHOD.

  METHOD compounding_condition.
    SELECT c~iobjcmp, o~fieldnm FROM rsdiobjcmp AS c
      INNER JOIN rsdiobj AS o ON o~iobjnm = c~iobjcmp AND o~objvers = 'A'
      WHERE c~iobjnm = @tables-basic AND c~objvers = 'A'
      ORDER BY c~posit ASCENDING
      INTO TABLE @DATA(compounding).
    LOOP AT compounding INTO DATA(compounded_with).
      READ TABLE fixed INTO DATA(compounding_value) WITH TABLE KEY iobjnm = compounded_with-iobjcmp.
      IF sy-subrc <> 0.
        fail( |{ characteristic } is compounded with { compounded_with-iobjcmp }, which must be fixed too| ).
      ENDIF.
      IF compounding_value-value CA `'`.
        fail( |{ compounded_with-iobjcmp }: a fixed value cannot contain a quote| ).
      ENDIF.
      result = |{ result }{ COND string( WHEN result IS NOT INITIAL THEN ` AND ` ) }| &&
               |{ compounded_with-fieldnm } = '{ compounding_value-value }'|.
    ENDLOOP.
  ENDMETHOD.

  METHOD provider_of_fact_table.
    LOOP AT providers( ) INTO DATA(entry).
      IF table NS entry-name.
        CONTINUE.
      ENDIF.
      DATA(facts) = COND string( WHEN entry-kind = c_kind-cube THEN cube_fact_table( CONV #( entry-name ) )
                                 ELSE adso_reporting_view( CONV #( entry-name ) ) ).
      IF facts = table.
        result = entry-name.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD cube_fact_table.
    DATA fact_table TYPE rsd_s_cube-facttab.
    CALL FUNCTION 'RSD_FACTTAB_GET_FOR_CUBE'
      EXPORTING
        i_infocube = cube
      IMPORTING
        e_facttab  = fact_table
      EXCEPTIONS
        name_error = 1
        OTHERS     = 2.
    IF sy-subrc = 0.
      result = fact_table.
    ENDIF.
  ENDMETHOD.

  METHOD adso_reporting_view.
    TRY.
        DATA(tables) = cl_rso_adso=>get_tablnm( adso ).
        result = VALUE #( tables[ dsotabtype = cl_rsdso_constants=>n_c_viewtype_reporting ]-name OPTIONAL ).
      CATCH cx_rs_not_found.
        CLEAR result.
    ENDTRY.
  ENDMETHOD.

  METHOD read_cube.
    DATA(fact_table) = cube_fact_table( cube ).
    IF fact_table IS INITIAL.
      fail( |InfoCube { cube }: BW gives no fact table| ).
    ENDIF.
    provider-fact_table = fact_table.
    DATA(columns) = columns_of( fact_table ).

    " the navigation attributes the cube switches on, which have no InfoObject of their own
    SELECT iobjnm FROM rsddimeiobj
      WHERE infocube = @cube AND objvers = 'A' AND iobjnm LIKE '%#_#_%' ESCAPE '#'
      INTO TABLE @cube_navigation.

    " the characteristics: a HANA-optimised InfoCube has one SID column per characteristic, no dimension tables
    SELECT d~iobjnm, o~iobjtp FROM rsddimeiobj AS d
      INNER JOIN rsdiobj AS o ON o~iobjnm = d~iobjnm AND o~objvers = 'A'
      WHERE d~infocube = @cube AND d~objvers = 'A'
      ORDER BY d~dimension ASCENDING, d~posit ASCENDING
      INTO TABLE @DATA(characteristics).
    LOOP AT characteristics INTO DATA(characteristic).
      CASE characteristic-iobjtp.
        WHEN 'CHA' OR 'TIM'.
          " BW's name: SID_<characteristic>, in a partner namespace /<generated namespace>/S_<name>
          DATA sid_column TYPE rs_char30.
          CALL FUNCTION 'RSD_SIDNM_GET_FROM_IOBJNM'
            EXPORTING
              i_iobjnm     = characteristic-iobjnm
            IMPORTING
              e_sidfieldnm = sid_column
            EXCEPTIONS
              name_error   = 1
              OTHERS       = 2.
          IF sy-subrc <> 0 OR sid_column IS INITIAL.
            fail( |InfoCube { cube }: BW gives no SID column for { characteristic-iobjnm }| ).
          ENDIF.
          READ TABLE columns INTO DATA(column) WITH TABLE KEY name = CONV string( sid_column ).
          IF sy-subrc <> 0.
            fail( |InfoCube { cube }: { fact_table } has no column { sid_column }; only HANA-optimised InfoCubes | &&
                  |are supported| ).
          ENDIF.
          DATA(with_sid) = characteristic( iobjnm      = characteristic-iobjnm
                                           iobjtp      = characteristic-iobjtp
                                           fact_column = column ).
          with_sid-fact_sid = abap_true.
          APPEND with_sid TO provider-characteristics.
        WHEN 'UNI'.
          APPEND VALUE #( iobjnm = characteristic-iobjnm reason = `unit or currency` ) TO provider-notes.
      ENDCASE.
    ENDLOOP.

    SELECT c~iobjnm, o~fieldnm FROM rsdcubeiobj AS c
      INNER JOIN rsdiobj AS o ON o~iobjnm = c~iobjnm AND o~objvers = 'A'
      WHERE c~infocube = @cube AND c~objvers = 'A' AND o~iobjtp = 'KYF'
      ORDER BY c~posit ASCENDING
      INTO TABLE @DATA(key_figures).
    LOOP AT key_figures INTO DATA(key_figure).
      READ TABLE columns INTO column WITH TABLE KEY name = CONV string( key_figure-fieldnm ).
      IF sy-subrc <> 0.
        APPEND VALUE #( iobjnm = key_figure-iobjnm reason = |no column { key_figure-fieldnm } in { fact_table }| )
          TO provider-notes.
        CONTINUE.
      ENDIF.
      APPEND key_figure( iobjnm = key_figure-iobjnm fact_column = column ) TO provider-key_figures.
    ENDLOOP.

    " fixed characteristics: the facts are read from the fact view, filtered on them, every field without namespace
    " (docs/bw-schema-design-guide.md, section 3.8)
    IF fixed IS INITIAL.
      RETURN.
    ENDIF.
    DATA(fact) = views->fact_layout( provider = cube fixed = fixed ).
    LOOP AT fact-notes INTO DATA(note).
      APPEND VALUE #( iobjnm = note-iobjnm reason = note-reason ) TO provider-notes.
    ENDLOOP.
    IF fact-columns IS INITIAL.
      RETURN.
    ENDIF.
    provider-fact_table = fact_view( provider = cube layout = fact ).
    LOOP AT provider-characteristics ASSIGNING FIELD-SYMBOL(<characteristic>).
      <characteristic>-fact_column-name = zzxxmla1_cl_bw_view_gen=>view_column( <characteristic>-fact_column-name ).
    ENDLOOP.
    LOOP AT provider-key_figures ASSIGNING FIELD-SYMBOL(<key_figure>).
      <key_figure>-fact_column-name = zzxxmla1_cl_bw_view_gen=>view_column( <key_figure>-fact_column-name ).
    ENDLOOP.
  ENDMETHOD.

  METHOD fact_view.
    " the view as it is, if it has every column it is generated with now; else a placeholder, generated on accept
    result = views->existing_fact_view( provider = provider fixed = fixed ).
    IF result IS NOT INITIAL.
      DATA(view_columns) = columns_of( result ).
      LOOP AT layout-columns INTO DATA(column).
        IF NOT line_exists( view_columns[ name = column-name ] ).
          CLEAR result.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.
    IF result IS INITIAL.
      result = zzxxmla1_cl_bw_view_gen=>fact_placeholder( provider ).
    ENDIF.
  ENDMETHOD.

  METHOD read_adso.
    DATA text     TYPE rsoadsodescr.
    DATA infoarea TYPE rsinfoarea.
    DATA objects  TYPE cl_rso_adso_api=>tn_t_object.
    TRY.
        cl_rso_adso_api=>read( EXPORTING i_adsonm               = adso
                                         i_with_enqueue         = rs_c_false
                                         i_with_authority_check = rs_c_false
                               IMPORTING e_text                 = text
                                         e_infoarea             = infoarea
                                         e_t_object             = objects ).
      CATCH cx_rs_all_msg INTO DATA(error).
        RAISE EXCEPTION TYPE zzxxmla1_cx_bw_provider
          EXPORTING error_message = |aDSO { adso }: { error->get_text( ) }|
                    previous      = error.
    ENDTRY.
    provider-text = text.
    provider-infoarea = infoarea.
    " the reporting view: inbound and active table together
    provider-fact_table = adso_reporting_view( adso ).
    IF provider-fact_table IS INITIAL.
      fail( |aDSO { adso }: BW gives no reporting view| ).
    ENDIF.
    DATA(columns) = columns_of( provider-fact_table ).

    LOOP AT objects INTO DATA(object).
      IF object-iobjnm IS INITIAL.
        APPEND VALUE #( iobjnm = object-fieldname reason = `field without InfoObject` ) TO provider-notes.
        CONTINUE.
      ENDIF.
      SELECT SINGLE iobjtp, fieldnm FROM rsdiobj WHERE iobjnm = @object-iobjnm AND objvers = 'A'
        INTO @DATA(infoobject).
      " the field BW names after the InfoObject, else the aDSO's own field name
      READ TABLE columns INTO DATA(column) WITH TABLE KEY name = CONV string( infoobject-fieldnm ).
      IF sy-subrc <> 0.
        READ TABLE columns INTO column WITH TABLE KEY name = CONV string( object-fieldname ).
      ENDIF.
      IF sy-subrc <> 0.
        APPEND VALUE #( iobjnm = object-iobjnm reason = |no column in { provider-fact_table }| ) TO provider-notes.
        CONTINUE.
      ENDIF.
      CASE infoobject-iobjtp.
        WHEN 'CHA' OR 'TIM'.
          APPEND characteristic( iobjnm          = object-iobjnm
                                 iobjtp          = infoobject-iobjtp
                                 fact_column     = column
                                 adso_navigation = object-navigational_attr_on ) TO provider-characteristics.
        WHEN 'KYF'.
          APPEND key_figure( iobjnm      = object-iobjnm
                             fact_column = column
                             aggregation = object-aggregation ) TO provider-key_figures.
        WHEN 'UNI'.
          APPEND VALUE #( iobjnm = object-iobjnm reason = `unit or currency` ) TO provider-notes.
      ENDCASE.
    ENDLOOP.

    " compounded or fixed characteristics: the facts are read from the fact view, which has the SID of each compounded
    " one whose compounding is not all fixed and is filtered on the fixed ones, every field named without namespace
    " (docs/bw-schema-design-guide.md, sections 3.7 and 3.8)
    DATA(fact) = views->fact_layout( provider = adso fixed = fixed ).
    LOOP AT fact-notes INTO DATA(note).
      APPEND VALUE #( iobjnm = note-iobjnm reason = note-reason ) TO provider-notes.
    ENDLOOP.
    IF fact-columns IS INITIAL.
      RETURN.
    ENDIF.
    provider-fact_table = fact_view( provider = adso layout = fact ).
    LOOP AT provider-characteristics ASSIGNING FIELD-SYMBOL(<characteristic>).
      READ TABLE fact-columns INTO DATA(fact_column) WITH KEY iobjnm = <characteristic>-iobjnm sid = abap_true.
      IF sy-subrc = 0.
        <characteristic>-fact_column = VALUE #( name = fact_column-name datatype = `INT4` length = 10 ).
        <characteristic>-fact_sid = abap_true.
      ELSE.
        <characteristic>-fact_column-name = zzxxmla1_cl_bw_view_gen=>view_column( <characteristic>-fact_column-name ).
      ENDIF.
    ENDLOOP.
    LOOP AT provider-key_figures ASSIGNING FIELD-SYMBOL(<key_figure>).
      <key_figure>-fact_column-name = zzxxmla1_cl_bw_view_gen=>view_column( <key_figure>-fact_column-name ).
    ENDLOOP.
  ENDMETHOD.

  METHOD characteristic.
    result = VALUE #( iobjnm = iobjnm text = text_of( iobjnm ) iobjtp = iobjtp fact_column = fact_column ).
    DATA(layout) = views->layout( characteristic = iobjnm fixed = fixed ).
    result-basic = layout-tables-basic.
    SELECT iobjcmp FROM rsdiobjcmp
      WHERE iobjnm = @result-basic AND objvers = 'A'
      ORDER BY posit ASCENDING
      INTO TABLE @DATA(compounding).
    result-compounding = VALUE #( FOR c IN compounding ( CONV string( c-iobjcmp ) ) ).
    READ TABLE layout-columns INTO DATA(key) WITH KEY iobjnm = result-basic text = abap_false.
    result-has_sids = xsdbool( sy-subrc = 0 ).
    IF result-has_sids = abap_false.
      RETURN.
    ENDIF.
    LOOP AT layout-notes INTO DATA(note).
      APPEND VALUE #( iobjnm = note-iobjnm reason = |{ note-reason } (of { iobjnm })| ) TO notes.
    ENDLOOP.
    result-key_column = VALUE #( name = key-name datatype = key-datatype length = key-length ).
    result-key_int_column = int_column( layout = layout column = key-name ).
    READ TABLE layout-columns INTO DATA(compound_key) WITH KEY name = zzxxmla1_cl_bw_view_gen=>c_compound_key.
    IF sy-subrc = 0.
      result-name_column = VALUE #( name = compound_key-name datatype = compound_key-datatype
                                    length = compound_key-length ).
    ENDIF.
    result-text_column = VALUE #( layout-columns[ iobjnm = result-basic text = abap_true ]-name OPTIONAL ).

    " the attributes of its basic characteristic, in BW's order
    LOOP AT layout-columns INTO DATA(column) WHERE text = abap_false AND iobjnm IS NOT INITIAL
                                                AND iobjnm <> result-basic.
      DATA(navigation) = xsdbool( line_exists( cube_navigation[ table_line = |{ iobjnm }__{ column-iobjnm }| ] )
                                  OR ( adso_navigation = abap_true AND column-navigation = abap_true ) ).
      APPEND VALUE #( iobjnm      = column-iobjnm
                      text        = text_of( CONV #( column-iobjnm ) )
                      column      = VALUE #( name = column-name datatype = column-datatype length = column-length )
                      int_column  = int_column( layout = layout column = column-name )
                      text_column = VALUE #( layout-columns[ iobjnm = column-iobjnm text = abap_true ]-name OPTIONAL )
                      navigation  = navigation ) TO result-attributes.
    ENDLOOP.

    " the view as it is, if it has every column it is generated with now; else the schema names a placeholder, and
    " accepting it generates the view again (it keeps its name)
    result-view = views->existing_view( characteristic = CONV #( result-basic ) fixed = fixed ).
    IF result-view IS NOT INITIAL.
      DATA(view_columns) = columns_of( result-view ).
      LOOP AT layout-columns INTO column.
        IF NOT line_exists( view_columns[ name = column-name ] ).
          CLEAR result-view.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD int_column.
    READ TABLE layout-columns INTO DATA(number) WITH KEY int_of = column.
    IF sy-subrc = 0.
      result = VALUE #( name = number-name datatype = number-datatype length = number-length ).
    ENDIF.
  ENDMETHOD.

  METHOD key_figure.
    SELECT SINGLE aggrgen, aggrexc, ncumfl FROM rsdkyf WHERE kyfnm = @iobjnm AND objvers = 'A' INTO @DATA(kyf).
    result = VALUE #( iobjnm         = iobjnm
                      text           = text_of( iobjnm )
                      fact_column    = fact_column
                      aggregation    = COND #( WHEN aggregation IS NOT INITIAL THEN aggregation ELSE kyf-aggrgen )
                      non_cumulative = xsdbool( kyf-ncumfl IS NOT INITIAL ) ).
    result-exception_aggregation = COND #( WHEN kyf-aggrexc IS NOT INITIAL THEN kyf-aggrexc ELSE result-aggregation ).
  ENDMETHOD.

  METHOD columns_of.
    SELECT fieldname, datatype, leng, decimals FROM dd03l
      WHERE tabname = @table AND as4local = 'A' AND fieldname NOT LIKE '.%'
      INTO TABLE @DATA(fields).
    LOOP AT fields INTO DATA(field).
      INSERT VALUE #( name = field-fieldname datatype = field-datatype length = field-leng decimals = field-decimals )
        INTO TABLE result.
    ENDLOOP.
  ENDMETHOD.

  METHOD text_of.
    SELECT SINGLE txtsh, txtlg FROM rsdiobjt
      WHERE langu = @sy-langu AND iobjnm = @iobjnm AND objvers = 'A'
      INTO @DATA(text).
    result = COND #( WHEN text-txtlg IS NOT INITIAL THEN text-txtlg
                     WHEN text-txtsh IS NOT INITIAL THEN text-txtsh
                     ELSE iobjnm ).
  ENDMETHOD.

  METHOD fail.
    RAISE EXCEPTION TYPE zzxxmla1_cx_bw_provider EXPORTING error_message = text.
  ENDMETHOD.

ENDCLASS.
