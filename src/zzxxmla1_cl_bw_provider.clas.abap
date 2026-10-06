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
"! RSD_SIDNM_GET_FROM_IOBJNM) and the characteristics' tables and views (ZZXXMLA1_CL_BW_VIEW_GEN). Each column comes with its DDIC type,
"! a characteristic with its time-independent attributes as columns of its view. What a schema cannot use is a note
"! with the reason: units and currencies, fields without InfoObject, time-dependent attributes. Nothing is changed.
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
      END OF ty_column.
    TYPES:
      "! a time-independent attribute of a characteristic; its column is the one of the attribute table, which the
      "! characteristic's view delivers without namespace (and a NUMC column as a number)
      BEGIN OF ty_attribute,
        iobjnm TYPE string,
        text   TYPE string,
        column TYPE ty_column,
      END OF ty_attribute,
      ty_t_attribute TYPE STANDARD TABLE OF ty_attribute WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_characteristic,
        iobjnm      TYPE string,
        text        TYPE string,
        iobjtp      TYPE string,     " CHA, or TIM for BW's time characteristics
        fact_column TYPE ty_column,  " InfoCube: the SID column; aDSO: the value
        has_sids    TYPE abap_bool,  " it has a SID table, so ZZXXMLA1_CL_BW_VIEW_GEN can generate its view
        view        TYPE string,     " the database view of its DDL source, initial if not generated yet
        key_column  TYPE ty_column,  " the characteristic's value as a column of the attribute (or SID) table
        attributes  TYPE ty_t_attribute,
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
        characteristics TYPE ty_t_characteristic,  " in the order of the provider
        key_figures     TYPE ty_t_key_figure,
        notes           TYPE ty_t_note,
      END OF ty_provider.

    "! The HANA-optimised InfoCubes and cube-type aDSOs, by name.
    METHODS providers
      RETURNING VALUE(result) TYPE ty_t_entry.
    "! The metadata of an InfoCube or aDSO.
    METHODS read
      IMPORTING name          TYPE csequence
      RETURNING VALUE(result) TYPE ty_provider
      RAISING   zzxxmla1_cx_bw_provider.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES ty_t_column TYPE HASHED TABLE OF ty_column WITH UNIQUE KEY name.

    DATA views TYPE REF TO zzxxmla1_cl_bw_view_gen.
    "! the notes of the attributes, collected while the characteristics are read
    DATA notes TYPE ty_t_note.

    METHODS read_cube
      IMPORTING cube     TYPE rsinfocube
      CHANGING  provider TYPE ty_provider
      RAISING   zzxxmla1_cx_bw_provider.
    METHODS read_adso
      IMPORTING adso     TYPE rsoadsonm
      CHANGING  provider TYPE ty_provider
      RAISING   zzxxmla1_cx_bw_provider.
    "! A characteristic with its view and attributes.
    METHODS characteristic
      IMPORTING iobjnm        TYPE rsiobjnm
                iobjtp        TYPE rsiobjtp
                fact_column   TYPE ty_column
      RETURNING VALUE(result) TYPE ty_characteristic.
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
    CLEAR notes.
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
    APPEND LINES OF notes TO result-notes.
  ENDMETHOD.

  METHOD read_cube.
    DATA fact_table TYPE rsd_s_cube-facttab.
    CALL FUNCTION 'RSD_FACTTAB_GET_FOR_CUBE'
      EXPORTING
        i_infocube = cube
      IMPORTING
        e_facttab  = fact_table
      EXCEPTIONS
        name_error = 1
        OTHERS     = 2.
    IF sy-subrc <> 0 OR fact_table IS INITIAL.
      fail( |InfoCube { cube }: BW gives no fact table| ).
    ENDIF.
    provider-fact_table = fact_table.
    DATA(columns) = columns_of( fact_table ).

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
          APPEND characteristic( iobjnm      = characteristic-iobjnm
                                 iobjtp      = characteristic-iobjtp
                                 fact_column = column ) TO provider-characteristics.
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
    TRY.
        DATA(tables) = cl_rso_adso=>get_tablnm( adso ).
        provider-fact_table = VALUE #( tables[ dsotabtype = cl_rsdso_constants=>n_c_viewtype_reporting ]-name OPTIONAL ).
      CATCH cx_rs_not_found.
        CLEAR provider-fact_table.
    ENDTRY.
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
          APPEND characteristic( iobjnm      = object-iobjnm
                                 iobjtp      = infoobject-iobjtp
                                 fact_column = column ) TO provider-characteristics.
        WHEN 'KYF'.
          APPEND key_figure( iobjnm      = object-iobjnm
                             fact_column = column
                             aggregation = object-aggregation ) TO provider-key_figures.
        WHEN 'UNI'.
          APPEND VALUE #( iobjnm = object-iobjnm reason = `unit or currency` ) TO provider-notes.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

  METHOD characteristic.
    result = VALUE #( iobjnm = iobjnm text = text_of( iobjnm ) iobjtp = iobjtp fact_column = fact_column ).
    DATA(tables) = views->tables( iobjnm ).
    result-has_sids = xsdbool( tables-sids IS NOT INITIAL AND tables-key_field IS NOT INITIAL ).
    IF result-has_sids = abap_false.
      RETURN.
    ENDIF.
    DATA(columns) = views->columns( tables ).
    READ TABLE columns INTO DATA(key) WITH KEY field = tables-key_field.
    IF sy-subrc <> 0.
      result-has_sids = abap_false.
      RETURN.
    ENDIF.
    result-view = views->existing_view( iobjnm ).
    result-key_column = VALUE #( name     = zzxxmla1_cl_bw_view_gen=>view_column( key-field )
                                 datatype = key-datatype
                                 length   = key-length ).
    IF tables-attributes IS INITIAL.
      RETURN.
    ENDIF.

    " the attributes of its basic characteristic, in BW's order
    SELECT a~attrinm, a~atrtimfl, o~fieldnm FROM rsdbchatr AS a
      INNER JOIN rsdiobj AS o ON o~iobjnm = a~attrinm AND o~objvers = 'A'
      WHERE a~chabasnm = @tables-basic AND a~objvers = 'A'
      ORDER BY a~posit ASCENDING
      INTO TABLE @DATA(attributes).
    LOOP AT attributes INTO DATA(attribute).
      IF attribute-atrtimfl IS NOT INITIAL AND attribute-atrtimfl <> '0'.
        APPEND VALUE #( iobjnm = attribute-attrinm reason = |time-dependent attribute of { iobjnm }| ) TO notes.
        CONTINUE.
      ENDIF.
      READ TABLE columns INTO DATA(column) WITH KEY field = attribute-fieldnm.
      IF sy-subrc <> 0.
        APPEND VALUE #( iobjnm = attribute-attrinm reason = |attribute of { iobjnm } without column in { tables-attributes }| )
          TO notes.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( iobjnm = attribute-attrinm
                      text   = text_of( attribute-attrinm )
                      column = VALUE #( name     = zzxxmla1_cl_bw_view_gen=>view_column( column-field )
                                        datatype = column-datatype
                                        length   = column-length ) ) TO result-attributes.
    ENDLOOP.
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
    SELECT fieldname, datatype, leng FROM dd03l
      WHERE tabname = @table AND as4local = 'A' AND fieldname NOT LIKE '.%'
      INTO TABLE @DATA(fields).
    LOOP AT fields INTO DATA(field).
      INSERT VALUE #( name = field-fieldname datatype = field-datatype length = field-leng ) INTO TABLE result.
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