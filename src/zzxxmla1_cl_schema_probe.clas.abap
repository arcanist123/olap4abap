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
"! The probe of a cube's facts (docs/bw-schema-design-guide.md, section 3.8): a characteristic the cube restricts in
"! mode restrict members has a dimension with the members of its selection only, while its facts are not filtered, so
"! the facts must hold no value the selection excludes (a query by it would drop them). Per such characteristic the
"! probe reads the excluded values in the cube's facts with their numbers of facts, at most c_max_values; none: ok.
"! The facts are the cube's as it reads them: the provider's facts filtered on the characteristics that filter the
"! cube (mode filter), so values outside the cube refuse nothing. They are read from BW's tables as the fact view is
"! made of them (ZZXXMLA1_CL_BW_VIEW_GEN=>fact_metadata), so the probe needs no generated view and runs before accept:
"! - an InfoCube's fact table holds SIDs: the facts are grouped on the SID column alone, then joined to the SID table,
"!   where the negated selection runs on the key field (the large table only grouped, the condition on the small
"!   one); a filtered characteristic is an inner join of its SID table with its condition on the key field;
"! - an aDSO's reporting view holds the values: the negated selection and the filters run on its fields.
"! A value is shown as the compounding and the own key separated by / (K4/2024013), an initial one as #.
"! Nothing is written.
CLASS zzxxmla1_cl_schema_probe DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! the excluded values listed per characteristic
    CONSTANTS c_max_values TYPE i VALUE 20.
    TYPES:
      "! an excluded value and the number of facts that hold it
      BEGIN OF ty_value,
        value TYPE string,
        facts TYPE int8,
      END OF ty_value,
      ty_t_value TYPE STANDARD TABLE OF ty_value WITH EMPTY KEY.
    TYPES:
      "! a characteristic in restrict members: ok if its facts hold no excluded value, else the first ones by value
      BEGIN OF ty_characteristic,
        name   TYPE string,
        ok     TYPE abap_bool,
        values TYPE ty_t_value,
      END OF ty_characteristic,
      ty_t_characteristic TYPE STANDARD TABLE OF ty_characteristic WITH EMPTY KEY.
    TYPES:
      "! a cube and its characteristics in restrict members (none: nothing to probe, ok)
      BEGIN OF ty_cube,
        cube            TYPE string,
        ok              TYPE abap_bool,
        characteristics TYPE ty_t_characteristic,
      END OF ty_cube,
      ty_t_cube TYPE STANDARD TABLE OF ty_cube WITH EMPTY KEY.
    TYPES:
      "! the statement of a probe and the number of its columns: the parts of the value, then the number of facts
      BEGIN OF ty_query,
        sql     TYPE string,
        columns TYPE i,
      END OF ty_query.

    METHODS constructor.
    "! The characteristics of a provider in restrict members of a selection, probed on the provider's facts filtered
    "! on the characteristics in filter the cube.
    METHODS probe
      IMPORTING provider      TYPE csequence
                selection     TYPE zzxxmla1_cl_bw_view_gen=>ty_t_selection
      RETURNING VALUE(result) TYPE ty_t_characteristic.
    "! A cube probed for the selection of its annotations; its provider is looked for only if it restricts members.
    "! Refused if the annotations are no selection or the cube is on no BW provider's facts.
    METHODS probe_cube
      IMPORTING cube          TYPE zzxxmla1_cl_schema_def=>ty_cube
      RETURNING VALUE(result) TYPE ty_cube
      RAISING   zzxxmla1_cx_bw_provider.
    "! Every cube of a schema probed.
    METHODS probe_schema
      IMPORTING !schema       TYPE zzxxmla1_cl_schema_def=>ty_schema
      RETURNING VALUE(result) TYPE ty_t_cube
      RAISING   zzxxmla1_cx_bw_provider.
    "! The message that refuses probed cubes, listing the excluded values; initial if all are ok.
    CLASS-METHODS refusal
      IMPORTING cubes         TYPE ty_t_cube
      RETURNING VALUE(result) TYPE string.
    "! The statement that reads a characteristic's excluded values in the facts; reads nothing. facts: the provider's
    "! facts with the characteristics in filter the cube; characteristic: its SID table, key field and compounding;
    "! rows: its selection. Initial if the characteristic is no field of the facts (nothing to probe).
    CLASS-METHODS build_query
      IMPORTING facts          TYPE zzxxmla1_cl_bw_view_gen=>ty_fact_metadata
                characteristic TYPE zzxxmla1_cl_bw_view_gen=>ty_metadata
                !rows          TYPE zzxxmla1_cl_bw_selection=>ty_t_row
      RETURNING VALUE(result)  TYPE ty_query.

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA views TYPE REF TO zzxxmla1_cl_bw_view_gen.

    "! The joins and conditions of the characteristics that filter the facts (alias a), as native SQL.
    CLASS-METHODS filter_source
      IMPORTING facts      TYPE zzxxmla1_cl_bw_view_gen=>ty_fact_metadata
      EXPORTING joins      TYPE string
                conditions TYPE string_table.
    "! The value of a probe's row: its parts but the last column, separated by /, an initial one as #.
    CLASS-METHODS value_of
      IMPORTING !row          TYPE string_table
      RETURNING VALUE(result) TYPE string.
ENDCLASS.



CLASS zzxxmla1_cl_schema_probe IMPLEMENTATION.

  METHOD constructor.
    views = NEW zzxxmla1_cl_bw_view_gen( ).
  ENDMETHOD.

  METHOD probe.
    DATA facts TYPE zzxxmla1_cl_bw_view_gen=>ty_fact_metadata.
    LOOP AT selection INTO DATA(restricted) WHERE mode = zzxxmla1_cl_bw_selection=>c_mode-members.
      IF facts IS INITIAL.
        facts = views->fact_metadata( provider = CONV #( provider ) selection = selection ).
      ENDIF.
      DATA(entry) = VALUE ty_characteristic( name = restricted-iobjnm ok = abap_true ).
      DATA(query) = build_query( facts          = facts
                                 characteristic = views->metadata( restricted-iobjnm )
                                 rows           = restricted-rows ).
      IF query IS NOT INITIAL.
        LOOP AT zzxxmla1_cl_sql=>query( sql = query-sql columns = query-columns ) INTO DATA(row).
          APPEND VALUE #( value = value_of( row ) facts = CONV int8( row[ query-columns ] ) ) TO entry-values.
        ENDLOOP.
        entry-ok = xsdbool( entry-values IS INITIAL ).
      ENDIF.
      APPEND entry TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD probe_cube.
    result = VALUE #( cube = cube-name ok = abap_true ).
    DATA(selection) = zzxxmla1_cl_schema_fix=>cube_selection( cube ).
    IF NOT line_exists( selection[ mode = zzxxmla1_cl_bw_selection=>c_mode-members ] ).
      RETURN.
    ENDIF.
    result-characteristics = probe( provider  = NEW zzxxmla1_cl_schema_fix( )->provider_of( cube )
                                    selection = selection ).
    result-ok = xsdbool( NOT line_exists( result-characteristics[ ok = abap_false ] ) ).
  ENDMETHOD.

  METHOD probe_schema.
    LOOP AT schema-cubes INTO DATA(cube).
      APPEND probe_cube( cube ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD refusal.
    LOOP AT cubes INTO DATA(cube).
      LOOP AT cube-characteristics INTO DATA(characteristic) WHERE ok = abap_false.
        DATA(values) = ``.
        LOOP AT characteristic-values INTO DATA(value).
          DATA(shown) = |{ value-value } ({ value-facts } { COND #( WHEN value-facts = 1 THEN `fact` ELSE `facts` ) })|.
          values = COND #( WHEN values IS INITIAL THEN shown ELSE |{ values }, { shown }| ).
        ENDLOOP.
        IF lines( characteristic-values ) >= c_max_values.
          values = |{ values }, ...|.
        ENDIF.
        DATA(text) = |Cube '{ cube-cube }' restricts the members of { characteristic-name }, but its facts hold | &&
                     |values its selection excludes: { values }. Filter the cube on it instead, or widen the | &&
                     |selection|.
        result = COND #( WHEN result IS INITIAL THEN text ELSE |{ result }; { text }| ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD build_query.
    READ TABLE facts-fields INTO DATA(field) WITH KEY iobjnm = characteristic-characteristic.
    IF sy-subrc <> 0 OR facts-fact_table IS INITIAL.
      RETURN.
    ENDIF.
    filter_source( EXPORTING facts = facts IMPORTING joins = DATA(joins) conditions = DATA(conditions) ).
    DATA(fact_table) = zzxxmla1_cl_sql=>quote( facts-fact_table ).
    DATA(own) = |a.{ zzxxmla1_cl_sql=>quote( field-field ) }|.
    DATA parts TYPE string_table.

    IF facts-cube = abap_true.
      " the SIDs grouped, then their values in the SID table
      IF characteristic-tables-sids IS INITIAL.
        RETURN.
      ENDIF.
      LOOP AT characteristic-compounding INTO DATA(compounding).
        APPEND |s.{ zzxxmla1_cl_sql=>quote( compounding-field ) }| TO parts.
      ENDLOOP.
      DATA(key) = |s.{ zzxxmla1_cl_sql=>quote( characteristic-tables-key_field ) }|.
      APPEND key TO parts.
      DATA(grouped) = |SELECT { own } AS probe_sid, COUNT(*) AS probe_facts FROM { fact_table } AS a{ joins }|.
      IF conditions IS NOT INITIAL.
        grouped = |{ grouped } WHERE { concat_lines_of( table = conditions sep = ` AND ` ) }|.
      ENDIF.
      grouped = |{ grouped } GROUP BY { own }|.
      result-sql = |SELECT { concat_lines_of( table = parts sep = `, ` ) }, p.probe_facts | &&
                   |FROM ( { grouped } ) AS p | &&
                   |INNER JOIN { zzxxmla1_cl_sql=>quote( characteristic-tables-sids ) } AS s | &&
                   |ON s."SID" = p.probe_sid | &&
                   |WHERE NOT ( { zzxxmla1_cl_bw_selection=>condition( rows = rows column = key ) } ) | &&
                   |ORDER BY { concat_lines_of( table = parts sep = `, ` ) } LIMIT { c_max_values }|.
    ELSE.
      " the values grouped where the selection excludes them
      LOOP AT characteristic-compounding INTO compounding.
        READ TABLE facts-fields INTO DATA(compounding_field) WITH KEY iobjnm = compounding-iobjnm.
        IF sy-subrc = 0.
          APPEND |a.{ zzxxmla1_cl_sql=>quote( compounding_field-field ) }| TO parts.
        ENDIF.
      ENDLOOP.
      APPEND own TO parts.
      APPEND |NOT ( { zzxxmla1_cl_bw_selection=>condition( rows = rows column = own ) } )| TO conditions.
      result-sql = |SELECT { concat_lines_of( table = parts sep = `, ` ) }, COUNT(*) | &&
                   |FROM { fact_table } AS a{ joins } | &&
                   |WHERE { concat_lines_of( table = conditions sep = ` AND ` ) } | &&
                   |GROUP BY { concat_lines_of( table = parts sep = `, ` ) } | &&
                   |ORDER BY { concat_lines_of( table = parts sep = `, ` ) } LIMIT { c_max_values }|.
    ENDIF.
    result-columns = lines( parts ) + 1.
  ENDMETHOD.

  METHOD filter_source.
    CLEAR: joins, conditions.
    DATA(count) = 0.
    LOOP AT facts-filtered INTO DATA(filtered).
      READ TABLE facts-fields INTO DATA(field) WITH KEY iobjnm = filtered-iobjnm.
      IF sy-subrc <> 0.
        " not a field of the facts: the fact view leaves it out too
        CONTINUE.
      ENDIF.
      DATA(column) = |a.{ zzxxmla1_cl_sql=>quote( field-field ) }|.
      IF facts-cube = abap_true.
        count = count + 1.
        DATA(alias) = |f{ count }|.
        joins = |{ joins } INNER JOIN { zzxxmla1_cl_sql=>quote( filtered-sids ) } AS { alias } | &&
                |ON { alias }."SID" = { column }|.
        column = |{ alias }.{ zzxxmla1_cl_sql=>quote( filtered-key_field ) }|.
      ENDIF.
      APPEND zzxxmla1_cl_bw_selection=>condition( rows = filtered-rows column = column ) TO conditions.
    ENDLOOP.
  ENDMETHOD.

  METHOD value_of.
    DATA(count) = lines( row ) - 1.
    LOOP AT row INTO DATA(part) TO count.
      DATA(shown) = COND string( WHEN part IS INITIAL THEN `#` ELSE part ).
      result = COND #( WHEN sy-tabix = 1 THEN shown ELSE |{ result }/{ shown }| ).
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
