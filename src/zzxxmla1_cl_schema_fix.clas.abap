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
"! Restricts characteristics of a cube by a selection (docs/bw-schema-design-guide.md, section 3.8,
"! ZZXXMLA1_CL_BW_SELECTION) as an edit of its schema (docs/schema-generator.md, Fixing): the cube gets the new
"! selection, and only the parts of the schema that depend on it follow; names, captions, hierarchies, levels,
"! properties, measures, double-click columns and members with facts stay as the user made them:
"! - the cube's annotations olap4abap.filter.CHARACTERISTIC (filter the cube) and olap4abap.members.CHARACTERISTIC
"!   (restrict members), one per restricted characteristic, its rows as text; olap4abap.fixed.CHARACTERISTIC = v of a
"!   schema fixed before selections is read as filter the cube with I EQ v and written with the new name;
"! - its fact table, the provider's facts for the selection (BW's table, the fact view or its placeholder; only the
"!   characteristics that filter the cube filter them), and as these name them the columns of its measures and the
"!   foreign keys of its dimensions;
"! - the tables of each dimension on a characteristic, found by the foreign key of its usage: the characteristic's
"!   view for the selection (or its placeholder, generated on accept), filtered on its own selection if it is
"!   restricted itself, so it is a dimension with the members of its selection (a fixed one with one member);
"! - a characteristic whose compounding becomes all fixed to one value (I EQ, either mode) is named by its own key
"!   (2024001): every NameColumn of its dimension on COMPOUND_KEY becomes its key column, an OrderByColumn on
"!   COMPOUND_KEY goes; one that becomes compounded again is named and ordered by COMPOUND_KEY on its key attribute,
"!   where that was named by its key.
"! The provider is the one whose facts the cube reads (a fact placeholder, a fact view of table ZZXXMLA1_VIEW or BW's
"! table), read for the old selection (the cube's annotations) and for the new one, as the proposal reads it; a table
"! of the schema is replaced only where it is the provider's or the characteristic's for the old one.
CLASS zzxxmla1_cl_schema_fix DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      "! a table of the schema replaced by another
      BEGIN OF ty_replaced,
        from TYPE string,
        to   TYPE string,
      END OF ty_replaced,
      ty_t_replaced TYPE STANDARD TABLE OF ty_replaced WITH EMPTY KEY.
    TYPES:
      "! what fixing changed besides the schema: the tables replaced, and the NUMC columns of the characteristics' tables
      "! that have a number (COLUMN_INT), which the UI names when a dimension is switched to numbers; and the provider
      "! read for the new selection (fix only)
      BEGIN OF ty_result,
        tables      TYPE ty_t_replaced,
        int_columns TYPE zzxxmla1_cl_schema_proposal=>ty_t_int_column,
        provider    TYPE zzxxmla1_cl_bw_provider=>ty_provider,
      END OF ty_result.
    TYPES:
      "! a characteristic of the cube's provider that can be restricted (it has a SID table): what its basic one is
      "! compounded with, its column in the facts, the dimension of the cube on it (a shared one by its name, else a
      "! private one; initial if the cube has none), its selection (mode and rows, initial if it has none) and whether
      "! that is one I EQ value, the value
      BEGIN OF ty_characteristic,
        name        TYPE string,
        text        TYPE string,
        compounding TYPE string_table,
        foreign_key TYPE string,
        dimension   TYPE string,
        shared      TYPE abap_bool,
        mode        TYPE c LENGTH 1,
        rows        TYPE zzxxmla1_cl_bw_selection=>ty_t_row,
        fixed       TYPE abap_bool,
        value       TYPE string,
      END OF ty_characteristic,
      ty_t_characteristic TYPE STANDARD TABLE OF ty_characteristic WITH EMPTY KEY.

    "! The selection of a cube: its annotations olap4abap.filter.CHARACTERISTIC and olap4abap.members.CHARACTERISTIC,
    "! and olap4abap.fixed.CHARACTERISTIC as filter the cube with I EQ; refused if an annotation is no selection or a
    "! characteristic has two.
    CLASS-METHODS cube_selection
      IMPORTING cube          TYPE zzxxmla1_cl_schema_def=>ty_cube
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_view_gen=>ty_t_selection
      RAISING   zzxxmla1_cx_bw_provider.
    "! The provider whose facts the cube reads: the one of a fact placeholder (ZZXXMLA1_F_...), of a fact view of table
    "! ZZXXMLA1_VIEW, or the InfoCube or aDSO whose fact table or reporting view it is; refused if there is none.
    METHODS provider_of
      IMPORTING cube          TYPE zzxxmla1_cl_schema_def=>ty_cube
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_bw_provider.
    "! The cube's provider read for the cube's selection.
    METHODS read_provider
      IMPORTING cube          TYPE zzxxmla1_cl_schema_def=>ty_cube
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_provider=>ty_provider
      RAISING   zzxxmla1_cx_bw_provider.
    "! Makes the cube restrict characteristics by the given selection, all it restricts (none: nothing); refused if
    "! the provider refuses the selection (zzxxmla1_cl_bw_provider->check_selection) or the cube does not read the
    "! provider's tables.
    METHODS fix
      IMPORTING cube          TYPE string
                selection     TYPE zzxxmla1_cl_bw_view_gen=>ty_t_selection
      CHANGING  !schema       TYPE zzxxmla1_cl_schema_def=>ty_schema
      RETURNING VALUE(result) TYPE ty_result
      RAISING   zzxxmla1_cx_bw_provider.
    "! The change of fix, reading nothing: old is the provider read for the cube's selection, new for the new one;
    "! views are the views of table ZZXXMLA1_VIEW, by which a table is known as a characteristic's or the facts'.
    CLASS-METHODS apply
      IMPORTING cube          TYPE string
                old           TYPE zzxxmla1_cl_bw_provider=>ty_provider
                new           TYPE zzxxmla1_cl_bw_provider=>ty_provider
                views         TYPE zzxxmla1_cl_bw_view_gen=>ty_t_view OPTIONAL
      CHANGING  !schema       TYPE zzxxmla1_cl_schema_def=>ty_schema
      RETURNING VALUE(result) TYPE ty_result
      RAISING   zzxxmla1_cx_bw_provider.
    "! The characteristics of a provider read for the cube's selection, with the cube's dimensions on them (by the
    "! foreign keys) and their selections.
    CLASS-METHODS characteristics
      IMPORTING cube          TYPE zzxxmla1_cl_schema_def=>ty_cube
                provider      TYPE zzxxmla1_cl_bw_provider=>ty_provider
      RETURNING VALUE(result) TYPE ty_t_characteristic.

  PROTECTED SECTION.
  PRIVATE SECTION.
    "! Replaces the tables of a dimension that are the characteristic's for the old selection, and switches its names
    "! between COMPOUND_KEY and the key when the characteristic stops or starts being compounded.
    CLASS-METHODS fix_dimension
      IMPORTING old       TYPE zzxxmla1_cl_bw_provider=>ty_characteristic
                new       TYPE zzxxmla1_cl_bw_provider=>ty_characteristic
                views     TYPE zzxxmla1_cl_bw_view_gen=>ty_t_view
      CHANGING  dimension TYPE zzxxmla1_cl_schema_def=>ty_dimension
                replaced  TYPE ty_t_replaced.
    "! Whether a table is the view of a characteristic: its view for the selection the provider was read for, its
    "! placeholder, or a view of table ZZXXMLA1_VIEW of its basic characteristic.
    CLASS-METHODS is_view_of
      IMPORTING table          TYPE string
                characteristic TYPE zzxxmla1_cl_bw_provider=>ty_characteristic
                views          TYPE zzxxmla1_cl_bw_view_gen=>ty_t_view
      RETURNING VALUE(result)  TYPE abap_bool.
    "! Whether a table is the provider's facts: its fact table for the selection it was read for, its fact
    "! placeholder, or a fact view of table ZZXXMLA1_VIEW of it.
    CLASS-METHODS is_facts_of
      IMPORTING table         TYPE string
                provider      TYPE zzxxmla1_cl_bw_provider=>ty_provider
                views         TYPE zzxxmla1_cl_bw_view_gen=>ty_t_view
      RETURNING VALUE(result) TYPE abap_bool.
    "! Sets a table name, listing it if it changes.
    CLASS-METHODS replace_table
      IMPORTING !to      TYPE string
      CHANGING  table    TYPE string
                replaced TYPE ty_t_replaced.
    CLASS-METHODS fail
      IMPORTING text TYPE string
      RAISING   zzxxmla1_cx_bw_provider.
ENDCLASS.



CLASS zzxxmla1_cl_schema_fix IMPLEMENTATION.

  METHOD cube_selection.
    IF cube-annotations IS NOT BOUND.
      RETURN.
    ENDIF.
    LOOP AT cube-annotations->array INTO DATA(annotation).
      DATA(restricted) = zzxxmla1_cl_bw_selection=>from_annotation( name = annotation-name value = annotation-cdata ).
      IF restricted IS INITIAL.
        CONTINUE.
      ENDIF.
      restricted-iobjnm = to_upper( restricted-iobjnm ).
      INSERT restricted INTO TABLE result.
      IF sy-subrc <> 0.
        fail( |Cube '{ cube-name }' has two selections of { restricted-iobjnm }| ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD provider_of.
    IF cube-fact-name <> `Table`.
      fail( |Cube '{ cube-name }' reads its facts from a { cube-fact-name }, not from a table of a provider| ).
    ENDIF.
    DATA(fact) = CAST zzxxmla1_cl_schema_def=>ty_table( cube-fact-def ).
    result = zzxxmla1_cl_bw_view_gen=>provider_of_fact_placeholder( fact->name ).
    IF result IS NOT INITIAL.
      RETURN.
    ENDIF.
    DATA(views) = NEW zzxxmla1_cl_bw_view_gen( )->registered( kind = zzxxmla1_cl_bw_view_gen=>c_kind-fact ).
    READ TABLE views INTO DATA(view) WITH KEY view_name = CONV viewname( fact->name ).
    IF sy-subrc = 0.
      result = view-characteristic.
      RETURN.
    ENDIF.
    result = NEW zzxxmla1_cl_bw_provider( )->provider_of_fact_table( fact->name ).
    IF result IS INITIAL.
      fail( |Cube '{ cube-name }' reads its facts from { fact->name }, which is of no InfoCube or aDSO| ).
    ENDIF.
  ENDMETHOD.

  METHOD read_provider.
    result = NEW zzxxmla1_cl_bw_provider( )->read( name = provider_of( cube ) selection = cube_selection( cube ) ).
  ENDMETHOD.

  METHOD fix.
    READ TABLE schema-cubes INTO DATA(target) WITH KEY name = cube.
    IF sy-subrc <> 0.
      fail( |The schema has no cube '{ cube }'| ).
    ENDIF.
    DATA(name) = provider_of( target ).
    DATA(reader) = NEW zzxxmla1_cl_bw_provider( ).
    DATA(old) = reader->read( name = name selection = cube_selection( target ) ).
    DATA(new) = reader->read( name = name selection = selection ).
    reader->check_selection( new ).
    result = apply( EXPORTING cube   = cube
                              old    = old
                              new    = new
                              views  = NEW zzxxmla1_cl_bw_view_gen( )->registered( )
                    CHANGING  schema = schema ).
    result-provider = new.
  ENDMETHOD.

  METHOD apply.
    READ TABLE schema-cubes ASSIGNING FIELD-SYMBOL(<cube>) WITH KEY name = cube.
    IF sy-subrc <> 0.
      fail( |The schema has no cube '{ cube }'| ).
    ENDIF.

    " the facts: the provider's for the new selection
    IF <cube>-fact-name <> `Table`.
      fail( |Cube '{ cube }' reads its facts from a { <cube>-fact-name }, not from a table of { old-name }| ).
    ENDIF.
    DATA(fact) = CAST zzxxmla1_cl_schema_def=>ty_table( <cube>-fact-def ).
    IF is_facts_of( table = fact->name provider = old views = views ) = abap_false.
      fail( |Cube '{ cube }' reads its facts from { fact->name }, not from those of { old-name } ({ old-fact_table })| ).
    ENDIF.
    replace_table( EXPORTING to = new-fact_table CHANGING table = fact->name replaced = result-tables ).

    " the selection, the annotations of fixing too
    IF <cube>-annotations IS NOT BOUND.
      <cube>-annotations = NEW #( ).
    ENDIF.
    LOOP AT <cube>-annotations->array INTO DATA(annotation).
      DATA(index) = sy-tabix.
      IF zzxxmla1_cl_bw_selection=>from_annotation( name = annotation-name value = annotation-cdata ) IS NOT INITIAL.
        DELETE <cube>-annotations->array INDEX index.
      ENDIF.
    ENDLOOP.
    LOOP AT new-selection INTO DATA(restricted).
      APPEND VALUE #( name  = zzxxmla1_cl_bw_selection=>annotation_name( characteristic = restricted-iobjnm
                                                                         mode           = restricted-mode )
                      cdata = zzxxmla1_cl_bw_selection=>rows_text( restricted-rows ) ) TO <cube>-annotations->array.
    ENDLOOP.
    IF <cube>-annotations->array IS INITIAL.
      CLEAR <cube>-annotations.
    ENDIF.

    " the measures' columns as the new facts name them
    LOOP AT <cube>-measures ASSIGNING FIELD-SYMBOL(<measure>) WHERE column IS NOT INITIAL.
      READ TABLE old-key_figures INTO DATA(old_key_figure) WITH KEY fact_column-name = <measure>-column.
      IF sy-subrc = 0.
        READ TABLE new-key_figures INTO DATA(new_key_figure) WITH KEY iobjnm = old_key_figure-iobjnm.
        IF sy-subrc = 0.
          <measure>-column = new_key_figure-fact_column-name.
        ENDIF.
      ENDIF.
    ENDLOOP.

    " each dimension of the cube on a characteristic, found by its foreign key in the old facts (each once, so a
    " foreign key changed to another's old one is not taken again)
    LOOP AT <cube>-dimensions INTO DATA(node).
      DATA(foreign_key) = ``.
      DATA usage TYPE REF TO zzxxmla1_cl_schema_def=>ty_dimension_usage.
      DATA own TYPE REF TO zzxxmla1_cl_schema_def=>ty_dimension.
      CLEAR: usage, own.
      CASE node-name.
        WHEN `DimensionUsage`.
          usage ?= node-def.
          foreign_key = usage->foreign_key.
        WHEN `Dimension`.
          own ?= node-def.
          foreign_key = own->foreign_key.
        WHEN OTHERS.
          CONTINUE.
      ENDCASE.
      READ TABLE old-characteristics INTO DATA(old_characteristic) WITH KEY fact_column-name = foreign_key.
      IF sy-subrc <> 0 OR foreign_key IS INITIAL.
        CONTINUE.
      ENDIF.
      READ TABLE new-characteristics INTO DATA(new_characteristic) WITH KEY iobjnm = old_characteristic-iobjnm.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      IF usage IS BOUND.
        usage->foreign_key = new_characteristic-fact_column-name.
        READ TABLE schema-dimensions ASSIGNING FIELD-SYMBOL(<shared>) WITH KEY name = usage->source.
        IF sy-subrc = 0.
          fix_dimension( EXPORTING old       = old_characteristic
                                   new       = new_characteristic
                                   views     = views
                         CHANGING  dimension = <shared>
                                   replaced  = result-tables ).
        ENDIF.
      ELSE.
        own->foreign_key = new_characteristic-fact_column-name.
        fix_dimension( EXPORTING old       = old_characteristic
                                 new       = new_characteristic
                                 views     = views
                       CHANGING  dimension = own->*
                                 replaced  = result-tables ).
      ENDIF.
    ENDLOOP.

    LOOP AT new-characteristics INTO new_characteristic WHERE has_sids = abap_true.
      LOOP AT zzxxmla1_cl_schema_proposal=>int_columns_of( new_characteristic ) INTO DATA(numeric).
        IF NOT line_exists( result-int_columns[ table = numeric-table column = numeric-column ] ).
          APPEND numeric TO result-int_columns.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD fix_dimension.
    DATA(table) = zzxxmla1_cl_schema_proposal=>table_of( new ).
    IF is_view_of( table = dimension-table characteristic = old views = views ) = abap_true.
      replace_table( EXPORTING to = table CHANGING table = dimension-table replaced = replaced ).
    ENDIF.
    LOOP AT dimension-hierarchies INTO DATA(hierarchy) WHERE relation-name = `Table`.
      " the node refers to the table, so it changes in the schema
      DATA(relation) = CAST zzxxmla1_cl_schema_def=>ty_table( hierarchy-relation-def ).
      IF is_view_of( table = relation->name characteristic = old views = views ) = abap_true.
        replace_table( EXPORTING to = table CHANGING table = relation->name replaced = replaced ).
      ENDIF.
    ENDLOOP.

    IF old-name_column IS NOT INITIAL AND new-name_column IS INITIAL.
      " its compounding all fixed: named by its own key
      LOOP AT dimension-attributes ASSIGNING FIELD-SYMBOL(<attribute>).
        IF <attribute>-name_column IS BOUND AND <attribute>-name_column->column_name = old-name_column-name.
          <attribute>-name_column->column_name = new-key_column-name.
          <attribute>-name_column->data_type = zzxxmla1_cl_schema_proposal=>data_type( new-key_column ).
        ENDIF.
        IF <attribute>-order_by_column IS BOUND AND <attribute>-order_by_column->column_name = old-name_column-name.
          CLEAR <attribute>-order_by_column.
        ENDIF.
      ENDLOOP.
    ELSEIF old-name_column IS INITIAL AND new-name_column IS NOT INITIAL.
      " compounded again: its key attribute named and ordered by COMPOUND_KEY, unless the user named it otherwise
      LOOP AT dimension-attributes ASSIGNING <attribute> WHERE usage = `Key`.
        IF <attribute>-name_column IS NOT BOUND
            OR <attribute>-name_column->column_name = old-key_column-name
            OR ( old-key_int_column IS NOT INITIAL
                 AND <attribute>-name_column->column_name = old-key_int_column-name ).
          <attribute>-name_column = NEW #( data_type   = zzxxmla1_cl_schema_proposal=>data_type( new-name_column )
                                           column_name = new-name_column-name ).
        ENDIF.
        IF <attribute>-order_by_column IS NOT BOUND.
          <attribute>-order_by_column = NEW #( data_type   = zzxxmla1_cl_schema_proposal=>data_type( new-name_column )
                                               column_name = new-name_column-name ).
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD is_view_of.
    result = xsdbool( table IS NOT INITIAL
                      AND ( table = zzxxmla1_cl_schema_proposal=>table_of( characteristic )
                            OR table = zzxxmla1_cl_bw_view_gen=>placeholder( characteristic-basic )
                            OR line_exists( views[ kind           = zzxxmla1_cl_bw_view_gen=>c_kind-characteristic
                                                   characteristic = CONV rsiobjnm( characteristic-basic )
                                                   view_name      = CONV viewname( table ) ] ) ) ).
  ENDMETHOD.

  METHOD is_facts_of.
    result = xsdbool( table IS NOT INITIAL
                      AND ( table = provider-fact_table
                            OR table = zzxxmla1_cl_bw_view_gen=>fact_placeholder( provider-name )
                            OR line_exists( views[ kind           = zzxxmla1_cl_bw_view_gen=>c_kind-fact
                                                   characteristic = CONV rsiobjnm( provider-name )
                                                   view_name      = CONV viewname( table ) ] ) ) ).
  ENDMETHOD.

  METHOD replace_table.
    IF table = to.
      RETURN.
    ENDIF.
    IF NOT line_exists( replaced[ from = table to = to ] ).
      APPEND VALUE #( from = table to = to ) TO replaced.
    ENDIF.
    table = to.
  ENDMETHOD.

  METHOD characteristics.
    LOOP AT provider-characteristics INTO DATA(characteristic) WHERE has_sids = abap_true.
      DATA(entry) = VALUE ty_characteristic( name        = characteristic-iobjnm
                                             text        = characteristic-text
                                             compounding = characteristic-compounding
                                             foreign_key = characteristic-fact_column-name ).
      READ TABLE provider-selection INTO DATA(restricted)
           WITH TABLE KEY iobjnm = CONV rsiobjnm( characteristic-iobjnm ).
      IF sy-subrc = 0.
        entry-mode = restricted-mode.
        entry-rows = restricted-rows.
        entry-fixed = zzxxmla1_cl_bw_selection=>is_single( restricted-rows ).
        entry-value = zzxxmla1_cl_bw_selection=>single_value( restricted-rows ).
      ENDIF.
      LOOP AT cube-dimensions INTO DATA(node).
        IF node-name = `DimensionUsage`.
          DATA(usage) = CAST zzxxmla1_cl_schema_def=>ty_dimension_usage( node-def ).
          IF usage->foreign_key = characteristic-fact_column-name.
            entry-dimension = usage->source.
            entry-shared = abap_true.
            EXIT.
          ENDIF.
        ELSEIF node-name = `Dimension`.
          DATA(own) = CAST zzxxmla1_cl_schema_def=>ty_dimension( node-def ).
          IF own->foreign_key = characteristic-fact_column-name.
            entry-dimension = own->name.
            EXIT.
          ENDIF.
        ENDIF.
      ENDLOOP.
      APPEND entry TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD fail.
    RAISE EXCEPTION TYPE zzxxmla1_cx_bw_provider EXPORTING error_message = text.
  ENDMETHOD.

ENDCLASS.
