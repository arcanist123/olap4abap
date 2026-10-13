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
"! Generates the CDS views a schema names as the dimension tables of a BW cube (docs/bw-schema-design-guide.md,
"! section 4): one view per basic characteristic, one row per SID. The SID table is left-outer-joined with everything
"! else, so every value with a SID is a row, with or without attributes (BW keeps none for its time characteristics,
"! whose attribute tables have only the initial row):
"! - the time-independent attributes (/BI0/P..., OBJVERS 'A') and the time-dependent ones (/BI0/Q..., OBJVERS 'A',
"!   valid on the key date 9999-12-31), joined on all their key fields;
"! - the texts of the characteristic and of every attribute that is a characteristic with texts (/BI0/T...), in
"!   language EN, valid on 9999-12-31, coalesce( text, key ) so that a value without text is named by its key. A text
"!   table is left out (a note) if it is client-dependent (the engine reads with native SQL, which filters no client,
"!   so a client-dependent table counts every fact once per client) or if a key field of it is not in the view.
"! The columns are SID, the key with its compounding (from the SID table), the characteristic's text (named like the
"! text field, TXTMD), then each attribute followed by its text (ATTRIBUTE_TXT), all as BW holds them and named
"! without their namespace (/BIC/ or another). A NUMC column is followed by its value as a number, COLUMN_INT (INT4 up
"! to 9 digits, INT8 up to 18, else DEC 31), for a schema that wants the number as the member's key or name; BW's value
"! is the NUMC one, the default (docs/mvp-scope.md, NUMC decision). The table and field names are BW's (RSD_CHKTAB_GET_FOR_CHA_BAS, RSDIOBJ-FIELDNM),
"! never built: their prefix depends on the namespace.
"! A reference characteristic (RSDCHA-CHABASNM, 0SOLD_TO -> 0CUSTOMER) has no tables of its own: its view is the one of
"! the basic characteristic, which schemas name for both.
"! A compounded characteristic (0FISCPER with 0FISCVARNT) is unique only by all key fields of its SID table: its view
"! also has COMPOUND_KEY, the compounding and the own key separated by / with BW's # for an initial value (K4/2024001,
"! #/#), which schemas name its members by (docs/bw-schema-design-guide.md, section 3.7).
"! The facts of a cube-type aDSO hold values, not SIDs, so the value of a compounded characteristic does not find one
"! row of its view: an aDSO with a compounded characteristic gets a fact view too, the reporting view with every field
"! (named without namespace) and SID_FIELD per compounded characteristic, from a left outer join to its SID table on
"! all key fields, which schemas join its view on.
"! A cube can restrict characteristics by a selection, a range table each (docs/bw-schema-design-guide.md, section 3.8,
"! ZZXXMLA1_CL_BW_SELECTION), in one of two modes, filter the cube or restrict members. A restricted characteristic
"! gets a view of its own filtered on its selection (WHERE on its key field), and a characteristic compounded with a
"! restricted one a view filtered on the selection of its compounding, its COMPOUND_KEY made of the key fields that
"! are not fixed to one value (I EQ) only, none if all are; the view is the same in both modes. The provider gets a
"! fact view filtered on the characteristics of mode filter the cube only, an InfoCube too (an inner join to the SID
"! table of each on the SID, WHERE on its key field there); none for a cube that only restricts members. An aDSO's
"! fact view has SID_FIELD for every compounded characteristic, also one whose compounding is all fixed, so that
"! restricting changes no key of a schema's dimension. A reference characteristic is not filtered on its own
"! selection: its view is its basic one's.
"! The views are DDIC-based CDS views, the kind NetWeaver 7.50 has, named by a number: database view ZZXXMLA1V and DDL
"! source ZZXXMLA1_C followed by the same 7 digits (a characteristic does not fit: 16 and 30 characters at most, and a
"! namespace has slashes). The database view is what the schema names. Each view is a row of table ZZXXMLA1_VIEW, keyed
"! by its DDL source, with its kind (C a characteristic's, F a provider's fact view), characteristic or provider and
"! selection (selection_text, initial for the plain view), and is found by these; a plain view of a run before the table is found by the DDL source's
"! description ("BW characteristic ZFMSTORE: ...", "BW aDSO ZCLVISITA: ...") and registered when it is generated again.
"! A view keeps its number when it is generated again, a new one gets the next free number. A source of an older name
"! (ZZXXMLA1_C_ followed by the characteristic) gets its number's name when it is generated again.
CLASS zzxxmla1_cl_bw_view_gen DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    "! The package of the generated views unless the caller names another: local, so that they are not objects of
    "! the package the code is installed in (an abapGit repository would offer to delete them).
    CONSTANTS c_default_package TYPE devclass VALUE '$TMP'.
    "! The view column that names a compounded characteristic's values by all their key fields.
    CONSTANTS c_compound_key TYPE string VALUE `COMPOUND_KEY`.
    "! The length of a selection in table ZZXXMLA1_VIEW (SSTRING).
    CONSTANTS c_selection_length TYPE i VALUE 1333.
    CONSTANTS:
      "! The kinds of view in table ZZXXMLA1_VIEW: a characteristic's view, a provider's fact view.
      BEGIN OF c_kind,
        characteristic TYPE c LENGTH 1 VALUE 'C',
        fact           TYPE c LENGTH 1 VALUE 'F',
      END OF c_kind.
    TYPES:
      "! the characteristic of the view (or the provider of a fact view, kind F), its selection (selection_text) and its
      "! names
      BEGIN OF ty_view,
        kind           TYPE c LENGTH 1,
        characteristic TYPE rsiobjnm,
        ddl_name       TYPE ddlname,
        view_name      TYPE viewname,
        selection      TYPE string,
      END OF ty_view,
      ty_t_view TYPE STANDARD TABLE OF ty_view WITH EMPTY KEY.
    TYPES:
      "! the characteristics a cube restricts, with their modes and rows (docs/bw-schema-design-guide.md, section 3.8)
      ty_t_selection TYPE zzxxmla1_cl_bw_selection=>ty_t_characteristic.
    TYPES:
      "! a characteristic a cube fixes to one value, BW's internal one, as fixing names it: a selection of mode filter
      "! the cube with one I EQ row (selection_of)
      BEGIN OF ty_fixed,
        iobjnm TYPE rsiobjnm,
        value  TYPE string,
      END OF ty_fixed,
      ty_t_fixed TYPE SORTED TABLE OF ty_fixed WITH UNIQUE KEY iobjnm.
    TYPES:
      "! The tables of a characteristic and the field of its key in them; a table is initial if the characteristic
      "! has none, or if the key field is not a column of it.
      BEGIN OF ty_tables,
        basic           TYPE rsiobjnm,   " whose tables they are: the characteristic, or the one it references
        sids            TYPE tabname,
        attributes      TYPE tabname,    " time-independent
        time_attributes TYPE tabname,    " time-dependent
        texts           TYPE tabname,
        key_field       TYPE fieldname,
      END OF ty_tables.
    TYPES:
      "! A column of a table: DDIC field, data type, length and whether it is a key field.
      BEGIN OF ty_column,
        field    TYPE fieldname,
        datatype TYPE datatype_d,
        length   TYPE i,
        key      TYPE abap_bool,
      END OF ty_column,
      ty_t_column TYPE STANDARD TABLE OF ty_column WITH EMPTY KEY.
    TYPES:
      "! A text table: its name, its columns and the field of the characteristic's value in it.
      BEGIN OF ty_text_table,
        name      TYPE tabname,
        key_field TYPE fieldname,
        columns   TYPE ty_t_column,
      END OF ty_text_table.
    TYPES:
      "! An attribute of the characteristic (RSDBCHATR): its field in the attribute tables, whether BW has it as a
      "! navigation attribute, and the text table of its characteristic (initial if it has none).
      BEGIN OF ty_attribute,
        iobjnm     TYPE rsiobjnm,
        field      TYPE fieldname,
        navigation TYPE abap_bool,
        texts      TYPE ty_text_table,
      END OF ty_attribute,
      ty_t_attribute TYPE STANDARD TABLE OF ty_attribute WITH EMPTY KEY.
    TYPES:
      "! A characteristic the compounded one is compounded with, and its field in the SID table.
      BEGIN OF ty_compounding,
        iobjnm TYPE rsiobjnm,
        field  TYPE fieldname,
      END OF ty_compounding,
      ty_t_compounding TYPE STANDARD TABLE OF ty_compounding WITH EMPTY KEY.
    TYPES:
      "! What BW has of a characteristic, all its view is made of; compounding: of the basic characteristic (RSDIOBJCMP).
      BEGIN OF ty_metadata,
        characteristic         TYPE rsiobjnm,
        tables                 TYPE ty_tables,
        sid_columns            TYPE ty_t_column,
        attribute_columns      TYPE ty_t_column,
        time_attribute_columns TYPE ty_t_column,
        texts                  TYPE ty_text_table,
        attributes             TYPE ty_t_attribute,
        compounding            TYPE ty_t_compounding,
      END OF ty_metadata.
    TYPES:
      "! A column of the view: its name, its expression in the DDL source, the DDIC type of the field it is made of
      "! (INT4, INT8 or DEC for the number of a NUMC column), the InfoObject whose value it is or, with text, whose
      "! text it is (initial for SID, compounding and numbers), whether that is a navigation attribute in BW, and for
      "! the number of a NUMC column the column it is the number of.
      BEGIN OF ty_view_column,
        name       TYPE string,
        expression TYPE string,
        datatype   TYPE string,
        length     TYPE i,
        iobjnm     TYPE string,
        text       TYPE abap_bool,
        navigation TYPE abap_bool,
        int_of     TYPE string,
      END OF ty_view_column,
      ty_t_view_column TYPE STANDARD TABLE OF ty_view_column WITH EMPTY KEY.
    TYPES:
      "! A join of the view: table, alias and the conditions, combined with AND; a left outer join, inner if so marked.
      BEGIN OF ty_join,
        table      TYPE tabname,
        alias      TYPE string,
        conditions TYPE string_table,
        inner      TYPE abap_bool,
      END OF ty_join,
      ty_t_join TYPE STANDARD TABLE OF ty_join WITH EMPTY KEY.
    TYPES:
      "! Something BW has that the view leaves out, and why.
      BEGIN OF ty_note,
        iobjnm TYPE string,
        reason TYPE string,
      END OF ty_note,
      ty_t_note TYPE STANDARD TABLE OF ty_note WITH EMPTY KEY.
    TYPES:
      "! The view of a characteristic: its tables, the joins to its SID table (alias s), its columns, the conditions
      "! of its selection and its compounding's (WHERE, combined with AND), their selection (selection_text, initial
      "! for the plain view) and what it leaves out. No columns if the characteristic has no SID table.
      BEGIN OF ty_layout,
        tables    TYPE ty_tables,
        joins     TYPE ty_t_join,
        columns   TYPE ty_t_view_column,
        filters   TYPE string_table,
        selection TYPE string,
        notes     TYPE ty_t_note,
      END OF ty_layout.
    TYPES:
      "! A field of the facts (an aDSO's reporting view, an InfoCube's fact table): DDIC field and type, the InfoObject
      "! whose value (on an InfoCube: SID) it is, initial for the technical fields.
      BEGIN OF ty_fact_field,
        field    TYPE fieldname,
        datatype TYPE datatype_d,
        length   TYPE i,
        iobjnm   TYPE rsiobjnm,
      END OF ty_fact_field,
      ty_t_fact_field TYPE STANDARD TABLE OF ty_fact_field WITH EMPTY KEY.
    TYPES:
      "! A characteristic the cube filters the facts on (mode filter the cube): its rows; on an InfoCube also its SID
      "! table, which the facts' SID is joined on, and its key field there, which the rows compare.
      BEGIN OF ty_filtered,
        iobjnm    TYPE rsiobjnm,
        rows      TYPE zzxxmla1_cl_bw_selection=>ty_t_row,
        sids      TYPE tabname,
        key_field TYPE fieldname,
      END OF ty_filtered,
      ty_t_filtered TYPE STANDARD TABLE OF ty_filtered WITH EMPTY KEY.
    TYPES:
      "! A compounded characteristic of an aDSO: its SID table, its own key field there and its compounding.
      BEGIN OF ty_compounded,
        iobjnm      TYPE rsiobjnm,
        sids        TYPE tabname,
        key_field   TYPE fieldname,
        compounding TYPE ty_t_compounding,
      END OF ty_compounded,
      ty_t_compounded TYPE STANDARD TABLE OF ty_compounded WITH EMPTY KEY.
    TYPES:
      "! What BW has of a provider that its fact view is made of: the facts (an aDSO's reporting view, an InfoCube's
      "! fact table), their fields, the compounded characteristics (an aDSO's, whose facts hold values) and the ones
      "! the cube filters the facts on.
      BEGIN OF ty_fact_metadata,
        provider   TYPE rsinfoprov,
        cube       TYPE abap_bool,
        fact_table TYPE tabname,
        fields     TYPE ty_t_fact_field,
        compounded TYPE ty_t_compounded,
        filtered   TYPE ty_t_filtered,
      END OF ty_fact_metadata.
    TYPES:
      "! A column of a fact view: name, expression, DDIC type, the InfoObject whose value it is, and whether it is the
      "! SID of a compounded characteristic.
      BEGIN OF ty_fact_column,
        name       TYPE string,
        expression TYPE string,
        datatype   TYPE string,
        length     TYPE i,
        iobjnm     TYPE string,
        sid        TYPE abap_bool,
      END OF ty_fact_column,
      ty_t_fact_column TYPE STANDARD TABLE OF ty_fact_column WITH EMPTY KEY.
    TYPES:
      "! The fact view of a provider: its facts (alias a), the joins to the SID tables, its columns, the conditions of
      "! the filtered characteristics (WHERE), their selection (selection_text) and what it leaves out. No columns if
      "! the provider needs none: nothing filtered and no compounded characteristic of an aDSO.
      BEGIN OF ty_fact_layout,
        fact_table TYPE tabname,
        joins      TYPE ty_t_join,
        columns    TYPE ty_t_fact_column,
        filters    TYPE string_table,
        selection  TYPE string,
        notes      TYPE ty_t_note,
      END OF ty_fact_layout.

    "! package: the package new views are created in.
    METHODS constructor
      IMPORTING package TYPE devclass DEFAULT c_default_package.

    "! Creates or updates the views of all characteristics of a cube, in the order of the cube.
    METHODS generate_cube
      IMPORTING cube          TYPE rsinfocube
      RETURNING VALUE(result) TYPE ty_t_view
      RAISING   cx_dd_ddl_exception.
    "! The database view of the characteristic's DDL source for a cube's selection (view_selection), if there is one;
    "! nothing is changed.
    METHODS existing_view
      IMPORTING characteristic TYPE rsiobjnm
                selection      TYPE ty_t_selection OPTIONAL
      RETURNING VALUE(result)  TYPE viewname.
    "! The table name a schema gives the view of a characteristic that is not generated yet (ZZXXMLA1_C_ followed by
    "! the characteristic): a name only for the schema, never one of the DDIC; accepting the schema generates the view
    "! (for the selection of the cube that uses it) and puts in its database view (ZZXXMLA1_CL_SCHEMA_API).
    CLASS-METHODS placeholder
      IMPORTING characteristic TYPE csequence
      RETURNING VALUE(result)  TYPE string.
    "! The characteristic of a placeholder, initial for any other name.
    CLASS-METHODS characteristic_of_placeholder
      IMPORTING table         TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! The view column of a table field: the field without its namespace (/BIC/ZFMSNAME -> ZFMSNAME).
    CLASS-METHODS view_column
      IMPORTING field         TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! Fixed values as table ZZXXMLA1_VIEW keys them (ZZXXMLA1_CL_BW_SELECTION=>selection_text): CHARACTERISTIC=value,
    "! sorted by characteristic, separated by ; (0FISCVARNT=K4); initial for none.
    CLASS-METHODS selection_text
      IMPORTING fixed         TYPE ty_t_fixed
      RETURNING VALUE(result) TYPE string.
    "! Fixed values as a selection: each characteristic filters the cube with one I EQ row.
    CLASS-METHODS selection_of
      IMPORTING fixed         TYPE ty_t_fixed
      RETURNING VALUE(result) TYPE ty_t_selection.
    "! The characteristics of a selection that filter the facts (mode filter the cube).
    CLASS-METHODS filter_selection
      IMPORTING selection     TYPE ty_t_selection
      RETURNING VALUE(result) TYPE ty_t_selection.
    "! BW's tables of a characteristic and its key field.
    METHODS tables
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ty_tables.
    "! What BW has of a characteristic: tables, their columns, attributes, texts and compounding.
    METHODS metadata
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ty_metadata.
    "! The view of a characteristic as it is generated for a cube's selection.
    METHODS layout
      IMPORTING characteristic TYPE rsiobjnm
                selection      TYPE ty_t_selection OPTIONAL
      RETURNING VALUE(result)  TYPE ty_layout.
    "! The view made of a characteristic's metadata; reads nothing. Of the restricted characteristics, in either mode,
    "! those of its compounding filter it (WHERE on their fields), and one fixed to a single I EQ value leaves
    "! COMPOUND_KEY, which is made of the other key fields only; the characteristic itself, if restricted and not a
    "! reference characteristic, filters it on its key field.
    CLASS-METHODS build_layout
      IMPORTING metadata      TYPE ty_metadata
                selection     TYPE ty_t_selection OPTIONAL
      RETURNING VALUE(result) TYPE ty_layout.
    "! Creates or updates the view of one characteristic for a cube's selection and activates it.
    METHODS generate
      IMPORTING characteristic TYPE rsiobjnm
                selection      TYPE ty_t_selection OPTIONAL
      RETURNING VALUE(result)  TYPE ty_view
      RAISING   cx_dd_ddl_exception.
    "! Deletes every view of a characteristic (DDL source and database view, the filtered ones too) if there is one:
    "! BW refuses to delete a characteristic whose data elements a view still uses. Returns whether there was one.
    METHODS delete
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE abap_bool
      RAISING   cx_dd_ddl_exception.
    "! The DDL source of the view of a characteristic.
    CLASS-METHODS ddl_source
      IMPORTING characteristic TYPE rsiobjnm
                view_name      TYPE viewname
                layout         TYPE ty_layout
      RETURNING VALUE(result)  TYPE string.
    "! The expression of COMPOUND_KEY: the key fields of the SID table (alias s) from the first compounding to the own
    "! key, separated by /, an initial value as #. CDS allows no CASE in concat, so it is one CASE with a branch per
    "! set of initial values, the larger sets first.
    CLASS-METHODS compound_key_expression
      IMPORTING columns       TYPE ty_t_column
      RETURNING VALUE(result) TYPE string.

    "! What BW has of a provider (InfoCube or aDSO) for its fact view: the facts, their fields, the compounded
    "! characteristics and those of the selection in mode filter the cube (the others leave the facts as they are).
    METHODS fact_metadata
      IMPORTING provider      TYPE rsinfoprov
                selection     TYPE ty_t_selection OPTIONAL
      RETURNING VALUE(result) TYPE ty_fact_metadata.
    "! The fact view of a provider as it is generated; no columns if it needs none.
    METHODS fact_layout
      IMPORTING provider      TYPE rsinfoprov
                selection     TYPE ty_t_selection OPTIONAL
      RETURNING VALUE(result) TYPE ty_fact_layout.
    "! The fact view made of a provider's metadata; reads nothing. Each filtered characteristic: on an aDSO the
    "! condition of its rows on its field, on an InfoCube its SID table inner-joined on the SID and the condition on
    "! its key field there.
    CLASS-METHODS build_fact_layout
      IMPORTING metadata      TYPE ty_fact_metadata
      RETURNING VALUE(result) TYPE ty_fact_layout.
    "! The DDL source of the fact view of a provider.
    CLASS-METHODS fact_ddl_source
      IMPORTING provider      TYPE rsinfoprov
                view_name     TYPE viewname
                layout        TYPE ty_fact_layout
      RETURNING VALUE(result) TYPE string.
    "! Creates or updates the fact view of a provider for a cube's selection and activates it (characteristic of the
    "! result: the provider); nothing if the provider needs none (the result is initial).
    METHODS generate_fact_view
      IMPORTING provider      TYPE rsinfoprov
                selection     TYPE ty_t_selection OPTIONAL
      RETURNING VALUE(result) TYPE ty_view
      RAISING   cx_dd_ddl_exception.
    "! The database view of the provider's fact view for a cube's selection, if there is one; nothing is changed.
    METHODS existing_fact_view
      IMPORTING provider      TYPE rsinfoprov
                selection     TYPE ty_t_selection OPTIONAL
      RETURNING VALUE(result) TYPE viewname.
    "! Deletes every fact view of a provider if there is one (BW cannot delete an aDSO a view selects from). Returns
    "! whether there was one.
    METHODS delete_fact_view
      IMPORTING provider      TYPE rsinfoprov
      RETURNING VALUE(result) TYPE abap_bool
      RAISING   cx_dd_ddl_exception.
    "! The table name a schema gives the fact view of a provider that is not generated yet (ZZXXMLA1_F_ followed by
    "! the provider), as placeholder does for a characteristic's view.
    CLASS-METHODS fact_placeholder
      IMPORTING provider      TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! The provider of a fact placeholder, initial for any other name.
    CLASS-METHODS provider_of_fact_placeholder
      IMPORTING table         TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! The selection of a characteristic's view for a cube's selection: the characteristics among the compounding of
    "! its basic one, and the characteristic itself if it is restricted and is the basic one (a reference
    "! characteristic's view is its basic one's); both modes.
    METHODS view_selection
      IMPORTING characteristic TYPE rsiobjnm
                selection      TYPE ty_t_selection
      RETURNING VALUE(result)  TYPE ty_t_selection.
    "! The views of table ZZXXMLA1_VIEW, of a kind (initial: both) and characteristic or provider (initial: all).
    METHODS registered
      IMPORTING kind          TYPE c DEFAULT space
                object_name   TYPE csequence DEFAULT space
      RETURNING VALUE(result) TYPE ty_t_view.
    "! Deletes the views with a selection whose database view is not among the used ones (the tables the schema files
    "! name), with their rows; the plain views stay. Returns the deleted ones.
    METHODS delete_unused
      IMPORTING used          TYPE string_table
      RETURNING VALUE(result) TYPE ty_t_view
      RAISING   cx_dd_ddl_exception.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CONSTANTS c_view_prefix TYPE string VALUE `ZZXXMLA1V`.
    CONSTANTS c_ddl_prefix TYPE string VALUE `ZZXXMLA1_C`.
    CONSTANTS c_placeholder_prefix TYPE string VALUE `ZZXXMLA1_C_`.
    CONSTANTS c_fact_placeholder_prefix TYPE string VALUE `ZZXXMLA1_F_`.
    "! the language of the texts and the key date of time-dependent data (docs/bw-schema-design-guide.md, Scope)
    CONSTANTS c_language TYPE string VALUE `E`.
    CONSTANTS c_key_date TYPE string VALUE `99991231`.
    TYPES:
      "! a field the view can join on, and the alias of its table
      BEGIN OF ty_source,
        field TYPE fieldname,
        alias TYPE string,
      END OF ty_source,
      ty_t_source TYPE STANDARD TABLE OF ty_source WITH EMPTY KEY.
    DATA package TYPE devclass.
    DATA handler TYPE REF TO if_dd_ddl_handler.
    "! the numbers handed out in this run, not yet in the DDIC
    DATA used_numbers TYPE STANDARD TABLE OF i WITH EMPTY KEY.

    METHODS ddl_handler
      RETURNING VALUE(result) TYPE REF TO if_dd_ddl_handler.
    "! The DDL source of the view of a database view: ZZXXMLA1_C and the view's number.
    CLASS-METHODS ddl_name
      IMPORTING view_name     TYPE viewname
      RETURNING VALUE(result) TYPE ddlname.
    "! The description of the DDL source of a characteristic's view: a label for ADT, and how a plain view of a run
    "! before table ZZXXMLA1_VIEW is found.
    CLASS-METHODS description
      IMPORTING characteristic TYPE rsiobjnm
                selection      TYPE string OPTIONAL
      RETURNING VALUE(result)  TYPE ddtext.
    "! The description of the DDL source of a provider's fact view, as description.
    CLASS-METHODS fact_description
      IMPORTING provider      TYPE rsinfoprov
                selection     TYPE string OPTIONAL
      RETURNING VALUE(result) TYPE ddtext.
    "! The selection as a label: CHARACTERISTIC = value or rows, separated by commas, without quotes (the label is a
    "! literal of the DDL source).
    CLASS-METHODS selection_label
      IMPORTING selection     TYPE string
      RETURNING VALUE(result) TYPE string.
    "! The DDL source of a view of a run before table ZZXXMLA1_VIEW, found by its description; initial if there is none.
    METHODS ddl_of_description
      IMPORTING !description  TYPE ddtext
      RETURNING VALUE(result) TYPE ddlname.
    "! The DDL source of the view of a kind, characteristic or provider and selection: the one of its row of table
    "! ZZXXMLA1_VIEW if that source exists (a row without source is deleted), else for the plain view one of a run
    "! before the table, by its description; initial if there is none.
    METHODS existing_ddl_name
      IMPORTING kind          TYPE c
                object_name   TYPE csequence
                selection     TYPE string
                !description  TYPE ddtext
      RETURNING VALUE(result) TYPE ddlname.
    "! The active database view of a DDL source; initial if there is none.
    METHODS view_of_ddl
      IMPORTING ddl_name      TYPE ddlname
      RETURNING VALUE(result) TYPE viewname.
    "! The names of the view of a kind, characteristic or provider and selection: the existing database view if it is
    "! numbered, else the next number. An active source can rename neither itself nor its database view: a source of
    "! another name (an older one, or one whose view is not numbered) is deleted, and its view is created again by
    "! the numbered source.
    METHODS numbered_names
      IMPORTING kind          TYPE c
                object_name   TYPE csequence
                selection     TYPE string
                !description  TYPE ddtext
      RETURNING VALUE(result) TYPE ty_view
      RAISING   cx_dd_ddl_exception.
    "! Saves a DDL source in the package, activates it and registers it in table ZZXXMLA1_VIEW.
    METHODS save
      IMPORTING kind         TYPE c
                object_name  TYPE csequence
                !view        TYPE ty_view
                !description TYPE ddtext
                source       TYPE string
      RAISING   cx_dd_ddl_exception.
    "! Deletes the views of a kind and characteristic or provider (DDL source, database view and row), and a plain
    "! one of a run before table ZZXXMLA1_VIEW; returns whether there was one.
    METHODS delete_all
      IMPORTING kind          TYPE c
                object_name   TYPE csequence
                !description  TYPE ddtext
      RETURNING VALUE(result) TYPE abap_bool
      RAISING   cx_dd_ddl_exception.
    "! The compounding of a basic characteristic in BW's order, with its fields (RSDIOBJCMP).
    METHODS compounding
      IMPORTING basic         TYPE rsiobjnm
      RETURNING VALUE(result) TYPE ty_t_compounding.
    "! The joins of a DDL source, a line per condition.
    CLASS-METHODS joins_source
      IMPORTING joins         TYPE ty_t_join
      RETURNING VALUE(result) TYPE string.
    "! The WHERE of a DDL source, after the select list; initial without conditions.
    CLASS-METHODS where_source
      IMPORTING filters       TYPE string_table
      RETURNING VALUE(result) TYPE string.
    "! The fact table of an InfoCube (RSD_FACTTAB_GET_FOR_CUBE); initial if BW gives none.
    METHODS cube_fact_table
      IMPORTING cube          TYPE rsinfocube
      RETURNING VALUE(result) TYPE tabname.
    "! The reporting view of an aDSO, its fields and its compounded characteristics.
    METHODS adso_fact_metadata
      CHANGING metadata TYPE ty_fact_metadata.
    "! The database view of an existing DDL source if it follows the numbering, else the next free number.
    METHODS view_name_for
      IMPORTING ddl_name      TYPE ddlname
      RETURNING VALUE(result) TYPE viewname.
    "! The number of a name of prefix and 7 digits, 0 for any other name.
    CLASS-METHODS number_of
      IMPORTING name          TYPE csequence
                prefix        TYPE string
      RETURNING VALUE(result) TYPE i.
    METHODS table_columns
      IMPORTING table         TYPE tabname
      RETURNING VALUE(result) TYPE ty_t_column.
    "! The table if it is active and has the key field, else initial.
    METHODS usable_table
      IMPORTING table         TYPE tabname
                key_field     TYPE fieldname
      RETURNING VALUE(result) TYPE tabname.
    "! The text table of a characteristic's tables, initial if it has none.
    METHODS text_table
      IMPORTING tables        TYPE ty_tables
      RETURNING VALUE(result) TYPE ty_text_table.
    "! Adds a field of a table as a column of the view, a NUMC field followed by its number (COLUMN_INT, a note
    "! instead if the name is too long or taken); source is the table's alias.
    CLASS-METHODS add_column
      IMPORTING column     TYPE ty_column
                source     TYPE string
                name       TYPE string
                iobjnm     TYPE csequence OPTIONAL
                navigation TYPE abap_bool OPTIONAL
      CHANGING  layout     TYPE ty_layout.
    "! A field as text, for coalesce with a text: CHAR as it is, other character-like types cast; initial if the
    "! type cannot be cast.
    CLASS-METHODS as_text
      IMPORTING column        TYPE ty_column
                source        TYPE string
      RETURNING VALUE(result) TYPE string.
    "! The join of a text table to a value (value_source.value_field), in language EN at the key date; reason is set
    "! instead if the text table cannot be joined to one row per value.
    CLASS-METHODS text_join
      IMPORTING texts        TYPE ty_text_table
                alias        TYPE string
                value_field  TYPE fieldname
                value_source TYPE string
                sources      TYPE ty_t_source
      EXPORTING join         TYPE ty_join
                text_field   TYPE fieldname
                reason       TYPE string.
    "! The column of a text, joined to a value; a note if it cannot be.
    CLASS-METHODS add_text
      IMPORTING texts   TYPE ty_text_table
                iobjnm  TYPE csequence
                value   TYPE ty_column
                source  TYPE string
                name    TYPE string
                sources TYPE ty_t_source
      CHANGING  layout  TYPE ty_layout.
ENDCLASS.

CLASS zzxxmla1_cl_bw_view_gen IMPLEMENTATION.

  METHOD constructor.
    me->package = package.
  ENDMETHOD.

  METHOD if_oo_adt_classrun~main.
    TRY.
        LOOP AT generate_cube( 'ZFMSALES' ) INTO DATA(view).
          out->write( |{ view-characteristic }: { view-ddl_name } / { view-view_name }| ).
        ENDLOOP.
      CATCH cx_dd_ddl_exception INTO DATA(error).
        out->write( |error: { error->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.

  METHOD generate_cube.
    " the characteristics of the cube; the package dimension and other technical or time objects are not
    SELECT d~iobjnm FROM rsddimeiobj AS d
      INNER JOIN rsdiobj AS o ON o~iobjnm = d~iobjnm AND o~objvers = 'A'
      WHERE d~infocube = @cube AND d~objvers = 'A' AND o~iobjtp = 'CHA'
      ORDER BY d~dimension ASCENDING, d~posit ASCENDING
      INTO TABLE @DATA(characteristics).
    LOOP AT characteristics INTO DATA(characteristic).
      APPEND generate( characteristic-iobjnm ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD generate.
    DATA(layout) = layout( characteristic = characteristic selection = selection ).
    DATA(text) = description( characteristic = characteristic selection = layout-selection ).
    result = numbered_names( kind        = c_kind-characteristic
                             object_name = characteristic
                             selection   = layout-selection
                             description = text ).
    result-characteristic = characteristic.
    result-selection = layout-selection.
    save( kind        = c_kind-characteristic
          object_name = characteristic
          view        = result
          description = text
          source      = ddl_source( characteristic = characteristic view_name = result-view_name layout = layout ) ).
  ENDMETHOD.

  METHOD numbered_names.
    DATA(existing) = existing_ddl_name( kind        = kind
                                        object_name = object_name
                                        selection   = selection
                                        description = description ).
    result-kind = kind.
    result-view_name = view_name_for( existing ).
    result-ddl_name = ddl_name( result-view_name ).
    IF existing IS NOT INITIAL AND existing <> result-ddl_name.
      ddl_handler( )->delete( existing ).
    ENDIF.
  ENDMETHOD.

  METHOD save.
    ddl_handler( )->save( name         = view-ddl_name
                          put_state    = 'N'
                          ddddlsrcv_wa = VALUE #( ddlname    = view-ddl_name
                                                  ddlanguage = sy-langu
                                                  ddtext     = description
                                                  source     = source ) ).
    cl_dd_ddl_handler=>if_dd_ddl_handler~write_tadir( objectname = view-ddl_name
                                                      devclass   = package
                                                      prid       = -1 ).
    ddl_handler( )->activate( view-ddl_name ).
    DATA(row) = VALUE zzxxmla1_view( kind        = kind
                                     object_name = object_name
                                     selection   = view-selection
                                     view_name   = view-view_name
                                     ddl_name    = view-ddl_name
                                     changed_by  = sy-uname ).
    GET TIME STAMP FIELD row-changed_at.
    " the table is keyed by the DDL source: a view of the same kind, object and selection under another name is gone
    DELETE FROM zzxxmla1_view
      WHERE kind = @row-kind AND object_name = @row-object_name AND selection = @row-selection
        AND ddl_name <> @row-ddl_name.
    MODIFY zzxxmla1_view FROM @row.
  ENDMETHOD.

  METHOD delete.
    result = delete_all( kind        = c_kind-characteristic
                         object_name = characteristic
                         description = description( characteristic ) ).
  ENDMETHOD.

  METHOD delete_all.
    DATA(object) = CONV zzxxmla1_view-object_name( object_name ).
    SELECT ddl_name FROM zzxxmla1_view WHERE kind = @kind AND object_name = @object INTO TABLE @DATA(rows).
    LOOP AT rows INTO DATA(row).
      SELECT SINGLE ddlname FROM ddddlsrc WHERE ddlname = @row-ddl_name INTO @DATA(found).
      IF sy-subrc = 0.
        ddl_handler( )->delete( found ).
        result = abap_true.
      ENDIF.
    ENDLOOP.
    DELETE FROM zzxxmla1_view WHERE kind = @kind AND object_name = @object.
    " a plain view of a run before the table
    DATA(older) = ddl_of_description( description ).
    IF older IS NOT INITIAL.
      ddl_handler( )->delete( older ).
      result = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD registered.
    SELECT kind, object_name, selection, view_name, ddl_name FROM zzxxmla1_view
      ORDER BY kind ASCENDING, object_name ASCENDING, selection ASCENDING
      INTO TABLE @DATA(rows).
    LOOP AT rows INTO DATA(row).
      IF ( kind IS INITIAL OR row-kind = kind ) AND ( object_name IS INITIAL OR row-object_name = object_name ).
        APPEND VALUE #( kind           = row-kind
                        characteristic = row-object_name
                        selection      = row-selection
                        view_name      = row-view_name
                        ddl_name       = row-ddl_name ) TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD delete_unused.
    LOOP AT registered( ) INTO DATA(view) WHERE selection IS NOT INITIAL.
      IF line_exists( used[ table_line = CONV string( view-view_name ) ] ).
        CONTINUE.
      ENDIF.
      SELECT SINGLE ddlname FROM ddddlsrc WHERE ddlname = @view-ddl_name INTO @DATA(found).
      IF sy-subrc = 0.
        ddl_handler( )->delete( found ).
      ENDIF.
      DELETE FROM zzxxmla1_view WHERE ddl_name = @view-ddl_name.
      APPEND view TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD generate_fact_view.
    DATA(layout) = fact_layout( provider = provider selection = selection ).
    IF layout-columns IS INITIAL.
      RETURN.
    ENDIF.
    DATA(text) = fact_description( provider = provider selection = layout-selection ).
    result = numbered_names( kind        = c_kind-fact
                             object_name = provider
                             selection   = layout-selection
                             description = text ).
    result-characteristic = provider.
    result-selection = layout-selection.
    save( kind        = c_kind-fact
          object_name = provider
          view        = result
          description = text
          source      = fact_ddl_source( provider = provider view_name = result-view_name layout = layout ) ).
  ENDMETHOD.

  METHOD delete_fact_view.
    result = delete_all( kind = c_kind-fact object_name = provider description = fact_description( provider ) ).
  ENDMETHOD.

  METHOD existing_fact_view.
    DATA(text) = zzxxmla1_cl_bw_selection=>selection_text( filter_selection( selection ) ).
    result = view_of_ddl( existing_ddl_name( kind        = c_kind-fact
                                             object_name = provider
                                             selection   = text
                                             description = fact_description( provider  = provider
                                                                             selection = text ) ) ).
  ENDMETHOD.

  METHOD fact_layout.
    result = build_fact_layout( fact_metadata( provider = provider selection = selection ) ).
  ENDMETHOD.

  METHOD fact_metadata.
    result-provider = provider.
    SELECT SINGLE infocube FROM rsdcube WHERE infocube = @provider AND objvers = 'A' INTO @DATA(cube).
    result-cube = xsdbool( sy-subrc = 0 ).
    IF result-cube = abap_true.
      result-fact_table = cube_fact_table( cube ).
      LOOP AT table_columns( result-fact_table ) INTO DATA(column).
        APPEND VALUE #( field = column-field datatype = column-datatype length = column-length ) TO result-fields.
      ENDLOOP.
      " the SID column of each characteristic, the field of each key figure
      SELECT d~iobjnm FROM rsddimeiobj AS d
        INNER JOIN rsdiobj AS o ON o~iobjnm = d~iobjnm AND o~objvers = 'A'
        WHERE d~infocube = @cube AND d~objvers = 'A' AND ( o~iobjtp = 'CHA' OR o~iobjtp = 'TIM' )
        INTO TABLE @DATA(characteristics).
      LOOP AT characteristics INTO DATA(characteristic).
        DATA sid_column TYPE rs_char30.
        CALL FUNCTION 'RSD_SIDNM_GET_FROM_IOBJNM'
          EXPORTING
            i_iobjnm     = characteristic-iobjnm
          IMPORTING
            e_sidfieldnm = sid_column
          EXCEPTIONS
            name_error   = 1
            OTHERS       = 2.
        READ TABLE result-fields ASSIGNING FIELD-SYMBOL(<sid>) WITH KEY field = sid_column.
        IF sy-subrc = 0 AND sid_column IS NOT INITIAL.
          <sid>-iobjnm = characteristic-iobjnm.
        ENDIF.
      ENDLOOP.
      SELECT c~iobjnm, o~fieldnm FROM rsdcubeiobj AS c
        INNER JOIN rsdiobj AS o ON o~iobjnm = c~iobjnm AND o~objvers = 'A'
        WHERE c~infocube = @cube AND c~objvers = 'A' AND o~iobjtp = 'KYF'
        INTO TABLE @DATA(key_figures).
      LOOP AT key_figures INTO DATA(key_figure).
        READ TABLE result-fields ASSIGNING FIELD-SYMBOL(<key_figure>) WITH KEY field = key_figure-fieldnm.
        IF sy-subrc = 0.
          <key_figure>-iobjnm = key_figure-iobjnm.
        ENDIF.
      ENDLOOP.
    ELSE.
      adso_fact_metadata( CHANGING metadata = result ).
    ENDIF.
    IF result-fact_table IS INITIAL.
      RETURN.
    ENDIF.
    " the characteristics that filter the facts; on an InfoCube their SID table and their key field there
    LOOP AT filter_selection( selection ) INTO DATA(restricted).
      DATA(entry) = VALUE ty_filtered( iobjnm = restricted-iobjnm rows = restricted-rows ).
      IF result-cube = abap_true.
        DATA(filtered_tables) = tables( restricted-iobjnm ).
        entry-sids = filtered_tables-sids.
        entry-key_field = filtered_tables-key_field.
      ENDIF.
      APPEND entry TO result-filtered.
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

  METHOD adso_fact_metadata.
    DATA objects TYPE cl_rso_adso_api=>tn_t_object.
    DATA adso TYPE rsoadsonm.
    adso = metadata-provider.
    TRY.
        cl_rso_adso_api=>read( EXPORTING i_adsonm               = adso
                                         i_with_enqueue         = rs_c_false
                                         i_with_authority_check = rs_c_false
                               IMPORTING e_t_object             = objects ).
        DATA(tables) = cl_rso_adso=>get_tablnm( adso ).
        metadata-fact_table = VALUE #( tables[ dsotabtype = cl_rsdso_constants=>n_c_viewtype_reporting ]-name
                                       OPTIONAL ).
      CATCH cx_rs_all_msg cx_rs_not_found.
        CLEAR metadata-fact_table.
    ENDTRY.
    IF metadata-fact_table IS INITIAL.
      RETURN.
    ENDIF.
    LOOP AT table_columns( metadata-fact_table ) INTO DATA(column).
      APPEND VALUE #( field = column-field datatype = column-datatype length = column-length ) TO metadata-fields.
    ENDLOOP.
    " the field of each InfoObject: the one BW names after it, else the aDSO's own field name (as the provider reads it)
    LOOP AT objects INTO DATA(object) WHERE iobjnm IS NOT INITIAL.
      SELECT SINGLE iobjtp, fieldnm FROM rsdiobj WHERE iobjnm = @object-iobjnm AND objvers = 'A'
        INTO @DATA(infoobject).
      READ TABLE metadata-fields ASSIGNING FIELD-SYMBOL(<field>) WITH KEY field = infoobject-fieldnm.
      IF sy-subrc <> 0.
        READ TABLE metadata-fields ASSIGNING <field> WITH KEY field = object-fieldname.
      ENDIF.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      <field>-iobjnm = object-iobjnm.
      IF infoobject-iobjtp <> 'CHA' AND infoobject-iobjtp <> 'TIM'.
        CONTINUE.
      ENDIF.
      " compounded: the compounding of its basic characteristic, whose SID table it has
      DATA(char_tables) = tables( object-iobjnm ).
      DATA(compounding) = compounding( char_tables-basic ).
      IF compounding IS NOT INITIAL AND char_tables-sids IS NOT INITIAL.
        APPEND VALUE #( iobjnm      = object-iobjnm
                        sids        = char_tables-sids
                        key_field   = char_tables-key_field
                        compounding = compounding ) TO metadata-compounded.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD build_fact_layout.
    result-fact_table = metadata-fact_table.
    " each filtered characteristic: on an aDSO the condition on its field, on an InfoCube an inner join of its SID table
    " on the SID and the condition on its key field there (WHERE: a condition of several rows is no join condition)
    DATA selection TYPE ty_t_selection.
    LOOP AT metadata-filtered INTO DATA(filtered).
      READ TABLE metadata-fields INTO DATA(filtered_field) WITH KEY iobjnm = filtered-iobjnm.
      IF sy-subrc <> 0.
        APPEND VALUE #( iobjnm = filtered-iobjnm reason = |filtered, but not a field of { metadata-provider }| )
          TO result-notes.
        CONTINUE.
      ENDIF.
      DATA(column) = |a.{ to_lower( filtered_field-field ) }|.
      IF metadata-cube = abap_true.
        DATA(filter_join) = VALUE ty_join( table = filtered-sids
                                           alias = |f{ lines( selection ) + 1 }|
                                           inner = abap_true ).
        APPEND |{ filter_join-alias }.sid = { column }| TO filter_join-conditions.
        APPEND filter_join TO result-joins.
        column = |{ filter_join-alias }.{ to_lower( filtered-key_field ) }|.
      ENDIF.
      APPEND zzxxmla1_cl_bw_selection=>condition( rows = filtered-rows column = column ) TO result-filters.
      INSERT VALUE #( iobjnm = filtered-iobjnm
                      mode   = zzxxmla1_cl_bw_selection=>c_mode-filter
                      rows   = filtered-rows ) INTO TABLE selection.
    ENDLOOP.
    result-selection = zzxxmla1_cl_bw_selection=>selection_text( selection ).
    IF metadata-compounded IS INITIAL AND selection IS INITIAL.
      RETURN.
    ENDIF.
    " every field of the facts, without namespace
    LOOP AT metadata-fields INTO DATA(field).
      APPEND VALUE #( name       = view_column( field-field )
                      expression = |a.{ to_lower( field-field ) }|
                      datatype   = field-datatype
                      length     = field-length
                      iobjnm     = field-iobjnm ) TO result-columns.
    ENDLOOP.
    " per compounded characteristic its SID: its SID table joined on all key fields; also if all its compounding is
    " fixed (it is then unique by its value), so that a schema keys its dimension the same way with and without
    DATA(sid_joins) = 0.
    LOOP AT metadata-compounded INTO DATA(compounded).
      READ TABLE metadata-fields INTO DATA(own) WITH KEY iobjnm = compounded-iobjnm.
      DATA(join) = VALUE ty_join( table = compounded-sids alias = |s{ sid_joins + 1 }| ).
      DATA(reason) = ``.
      LOOP AT compounded-compounding INTO DATA(compounding).
        READ TABLE metadata-fields INTO DATA(value) WITH KEY iobjnm = compounding-iobjnm.
        IF sy-subrc <> 0.
          reason = |compounded with { compounding-iobjnm }, which is not a field of the aDSO|.
          EXIT.
        ENDIF.
        APPEND |{ join-alias }.{ to_lower( compounding-field ) } = a.{ to_lower( value-field ) }| TO join-conditions.
      ENDLOOP.
      DATA(name) = |SID_{ view_column( own-field ) }|.
      IF reason IS INITIAL AND line_exists( result-columns[ name = name ] ).
        reason = |SID column { name } is the name of another column|.
      ENDIF.
      IF reason IS NOT INITIAL.
        APPEND VALUE #( iobjnm = compounded-iobjnm reason = reason ) TO result-notes.
        CONTINUE.
      ENDIF.
      APPEND |{ join-alias }.{ to_lower( compounded-key_field ) } = a.{ to_lower( own-field ) }| TO join-conditions.
      APPEND join TO result-joins.
      sid_joins = sid_joins + 1.
      APPEND VALUE #( name       = name
                      expression = |{ join-alias }.sid|
                      datatype   = `INT4`
                      length     = 10
                      iobjnm     = compounded-iobjnm
                      sid        = abap_true ) TO result-columns.
    ENDLOOP.
    " neither a SID column nor a filtered characteristic: no fact view needed
    IF result-joins IS INITIAL AND result-filters IS INITIAL.
      CLEAR result-columns.
    ENDIF.
  ENDMETHOD.

  METHOD fact_ddl_source.
    DATA(nl) = cl_abap_char_utilities=>newline.
    result = |@AbapCatalog.sqlViewName: '{ view_name }'| && nl &&
             |@AbapCatalog.compiler.compareFilter: true| && nl &&
             |@AccessControl.authorizationCheck: #NOT_REQUIRED| && nl &&
             |@EndUserText.label: '{ fact_description( provider = provider selection = layout-selection ) }'| && nl &&
             |define view { ddl_name( view_name ) }| && nl &&
             |  as select from { to_lower( layout-fact_table ) } as a| && nl &&
             joins_source( layout-joins ) &&
             |\{| && nl.
    LOOP AT layout-columns INTO DATA(column).
      result = result && COND string( WHEN sy-tabix = 1 THEN `  ` ELSE |,{ nl }  | ) &&
               |{ column-expression } as { column-name }|.
    ENDLOOP.
    result = result && nl && |\}| && where_source( layout-filters ) && nl.
  ENDMETHOD.

  METHOD compound_key_expression.
    " the key fields as text: CHAR as it is (concat takes the other character-like types too), initial in BW is blank,
    " for NUMC all zeros
    DATA(count) = lines( columns ).
    DATA fields TYPE string_table.
    DATA initials TYPE string_table.
    LOOP AT columns INTO DATA(column).
      APPEND |s.{ to_lower( column-field ) }| TO fields.
      APPEND COND string( WHEN column-datatype = 'NUMC' OR column-datatype = 'DATS' OR column-datatype = 'TIMS'
                          THEN |'{ repeat( val = `0` occ = column-length ) }'|
                          ELSE `' '` ) TO initials.
    ENDLOOP.
    " the sets of initial values as bit masks, the larger sets first; the empty set is the ELSE
    DATA masks TYPE STANDARD TABLE OF i WITH EMPTY KEY.
    DATA(size) = count.
    WHILE size > 0.
      DO ipow( base = 2 exp = count ) - 1 TIMES.
        DATA(mask) = sy-index.
        DATA(bits) = 0.
        DO count TIMES.
          IF ( mask DIV ipow( base = 2 exp = sy-index - 1 ) ) MOD 2 = 1.
            bits = bits + 1.
          ENDIF.
        ENDDO.
        IF bits = size.
          APPEND mask TO masks.
        ENDIF.
      ENDDO.
      size = size - 1.
    ENDWHILE.
    APPEND 0 TO masks.

    result = `case`.
    LOOP AT masks INTO mask.
      " the parts of this branch: # for an initial value, else the field; literals next to each other are one
      DATA parts TYPE string_table.
      DATA conditions TYPE string_table.
      CLEAR: parts, conditions.
      DATA(literal) = ``.
      DO count TIMES.
        DATA(position) = sy-index.
        IF position > 1.
          literal = literal && `/`.
        ENDIF.
        IF ( mask DIV ipow( base = 2 exp = position - 1 ) ) MOD 2 = 1.
          literal = literal && `#`.
          APPEND |{ fields[ position ] } = { initials[ position ] }| TO conditions.
        ELSE.
          IF literal IS NOT INITIAL.
            APPEND |'{ literal }'| TO parts.
            CLEAR literal.
          ENDIF.
          APPEND fields[ position ] TO parts.
        ENDIF.
      ENDDO.
      IF literal IS NOT INITIAL.
        APPEND |'{ literal }'| TO parts.
      ENDIF.
      DATA(value) = parts[ 1 ].
      LOOP AT parts INTO DATA(part) FROM 2.
        value = |concat( { value }, { part } )|.
      ENDLOOP.
      result = result && cl_abap_char_utilities=>newline && `             ` &&
               COND string( WHEN mask = 0 THEN |else { value } end|
                            ELSE |when { concat_lines_of( table = conditions sep = ` and ` ) } then { value }| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD layout.
    result = build_layout( metadata = metadata( characteristic ) selection = selection ).
  ENDMETHOD.

  METHOD build_layout.
    result-tables = metadata-tables.
    IF metadata-tables-sids IS INITIAL.
      RETURN.
    ENDIF.
    DATA(key_field) = metadata-tables-key_field.

    " the fields joins can use: the key and its compounding from the SID table, the attributes from theirs
    DATA sources TYPE ty_t_source.
    LOOP AT metadata-sid_columns INTO DATA(column) WHERE key = abap_true.
      APPEND VALUE #( field = column-field alias = `s` ) TO sources.
    ENDLOOP.
    IF metadata-tables-attributes IS NOT INITIAL.
      DATA(join) = VALUE ty_join( table = metadata-tables-attributes alias = `p` ).
      LOOP AT metadata-attribute_columns INTO column WHERE key = abap_true AND field <> 'OBJVERS'.
        APPEND |p.{ to_lower( column-field ) } = s.{ to_lower( column-field ) }| TO join-conditions.
      ENDLOOP.
      APPEND |p.objvers = 'A'| TO join-conditions.
      APPEND join TO result-joins.
      LOOP AT metadata-attribute_columns INTO column WHERE key = abap_false AND field <> 'CHANGED'.
        APPEND VALUE #( field = column-field alias = `p` ) TO sources.
      ENDLOOP.
    ENDIF.
    IF metadata-tables-time_attributes IS NOT INITIAL.
      join = VALUE ty_join( table = metadata-tables-time_attributes alias = `q` ).
      LOOP AT metadata-time_attribute_columns INTO column
           WHERE key = abap_true AND field <> 'OBJVERS' AND field <> 'DATETO'.
        APPEND |q.{ to_lower( column-field ) } = s.{ to_lower( column-field ) }| TO join-conditions.
      ENDLOOP.
      APPEND |q.objvers = 'A'| TO join-conditions.
      APPEND |q.dateto = '{ c_key_date }'| TO join-conditions.
      APPEND join TO result-joins.
      LOOP AT metadata-time_attribute_columns INTO column
           WHERE key = abap_false AND field <> 'CHANGED' AND field <> 'DATEFROM'.
        APPEND VALUE #( field = column-field alias = `q` ) TO sources.
      ENDLOOP.
    ENDIF.

    " SID, the key with its compounding, the characteristic's text
    APPEND VALUE #( name = `SID` expression = `s.sid` datatype = `INT4` length = 10 ) TO result-columns.
    LOOP AT metadata-sid_columns INTO column WHERE key = abap_true.
      add_column( EXPORTING column = column
                            source = `s`
                            name   = view_column( column-field )
                            iobjnm = COND string( WHEN column-field = key_field THEN metadata-tables-basic )
                  CHANGING  layout = result ).
    ENDLOOP.
    " the selection of its compounding filters the view, in either mode (docs/bw-schema-design-guide.md, section 3.8);
    " a field fixed to one value names no value
    DATA fixed_fields TYPE STANDARD TABLE OF fieldname WITH EMPTY KEY.
    DATA view_selection TYPE ty_t_selection.
    LOOP AT metadata-compounding INTO DATA(compounding).
      READ TABLE selection INTO DATA(restricted) WITH TABLE KEY iobjnm = compounding-iobjnm.
      IF sy-subrc = 0.
        INSERT restricted INTO TABLE view_selection.
        IF zzxxmla1_cl_bw_selection=>is_single( restricted-rows ) = abap_true.
          APPEND compounding-field TO fixed_fields.
        ENDIF.
        APPEND zzxxmla1_cl_bw_selection=>condition( rows   = restricted-rows
                                                    column = |s.{ to_lower( compounding-field ) }| ) TO result-filters.
      ENDIF.
    ENDLOOP.
    " restricted itself: the members of its selection; not a reference characteristic, whose view others share
    READ TABLE selection INTO DATA(own) WITH TABLE KEY iobjnm = metadata-tables-basic.
    IF sy-subrc = 0 AND metadata-characteristic = metadata-tables-basic.
      INSERT own INTO TABLE view_selection.
      APPEND zzxxmla1_cl_bw_selection=>condition( rows = own-rows column = |s.{ to_lower( key_field ) }| )
        TO result-filters.
    ENDIF.
    result-selection = zzxxmla1_cl_bw_selection=>selection_text( view_selection ).
    " compounded: the name of a value by all key fields that are not fixed
    DATA key_columns TYPE ty_t_column.
    LOOP AT metadata-sid_columns INTO column WHERE key = abap_true.
      IF NOT line_exists( fixed_fields[ table_line = column-field ] ).
        APPEND column TO key_columns.
      ENDIF.
    ENDLOOP.
    IF lines( key_columns ) > 1.
      APPEND VALUE #( name       = c_compound_key
                      expression = compound_key_expression( key_columns )
                      datatype   = `CHAR`
                      length     = REDUCE i( INIT n = lines( key_columns ) - 1
                                             FOR c IN key_columns NEXT n = n + c-length ) ) TO result-columns.
    ENDIF.
    IF metadata-texts IS NOT INITIAL.
      add_text( EXPORTING texts   = metadata-texts
                          iobjnm  = metadata-tables-basic
                          value   = VALUE #( metadata-sid_columns[ field = key_field ] OPTIONAL )
                          source  = `s`
                          name    = ``
                          sources = sources
                CHANGING  layout  = result ).
    ENDIF.

    " each attribute, followed by its text
    LOOP AT sources INTO DATA(source) WHERE alias <> `s`.
      DATA(columns) = COND ty_t_column( WHEN source-alias = `p` THEN metadata-attribute_columns
                                        ELSE metadata-time_attribute_columns ).
      column = columns[ field = source-field ].
      DATA(attribute) = VALUE ty_attribute( metadata-attributes[ field = column-field ] OPTIONAL ).
      DATA(name) = view_column( column-field ).
      add_column( EXPORTING column     = column
                            source     = source-alias
                            name       = name
                            iobjnm     = attribute-iobjnm
                            navigation = attribute-navigation
                  CHANGING  layout     = result ).
      IF attribute-texts IS NOT INITIAL.
        add_text( EXPORTING texts   = attribute-texts
                            iobjnm  = attribute-iobjnm
                            value   = column
                            source  = source-alias
                            name    = |{ name }_TXT|
                            sources = sources
                  CHANGING  layout  = result ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD add_text.
    DATA join TYPE ty_join.
    DATA text_field TYPE fieldname.
    DATA reason TYPE string.
    " the characteristic's text is t, the attributes' texts t1, t2, ...
    DATA(alias) = `t`.
    IF name IS NOT INITIAL.
      DATA(number) = 1.
      LOOP AT layout-joins TRANSPORTING NO FIELDS WHERE alias CP 't+*'.
        number = number + 1.
      ENDLOOP.
      alias = |t{ number }|.
    ENDIF.
    text_join( EXPORTING texts        = texts
                         alias        = alias
                         value_field  = value-field
                         value_source = source
                         sources      = sources
               IMPORTING join         = join
                         text_field   = text_field
                         reason       = reason ).
    DATA(column_name) = COND string( WHEN name IS INITIAL THEN view_column( text_field ) ELSE name ).
    IF reason IS INITIAL AND strlen( column_name ) > 30.
      reason = |text column { column_name } is longer than 30 characters|.
    ELSEIF reason IS INITIAL AND line_exists( layout-columns[ name = column_name ] ).
      reason = |text column { column_name } is the name of another column|.
    ENDIF.
    IF reason IS NOT INITIAL.
      APPEND VALUE #( iobjnm = iobjnm reason = |text not in the view: { reason }| ) TO layout-notes.
      RETURN.
    ENDIF.
    APPEND join TO layout-joins.
    DATA(text) = |{ alias }.{ to_lower( text_field ) }|.
    DATA(key) = as_text( column = value source = source ).
    APPEND VALUE #( name       = column_name
                    expression = COND #( WHEN key IS INITIAL THEN text ELSE |coalesce( { text }, { key } )| )
                    datatype   = `CHAR`
                    length     = texts-columns[ field = text_field ]-length
                    iobjnm     = iobjnm
                    text       = abap_true ) TO layout-columns.
  ENDMETHOD.

  METHOD text_join.
    CLEAR: join, text_field, reason.
    join = VALUE #( table = texts-name alias = alias ).
    LOOP AT texts-columns INTO DATA(column) WHERE key = abap_true.
      DATA(field) = |{ alias }.{ to_lower( column-field ) }|.
      IF column-datatype = 'CLNT'.
        reason = |{ texts-name } is client-dependent|.
        RETURN.
      ELSEIF column-field = texts-key_field.
        APPEND |{ field } = { value_source }.{ to_lower( value_field ) }| TO join-conditions.
      ELSEIF column-field = 'LANGU'.
        APPEND |{ field } = '{ c_language }'| TO join-conditions.
      ELSEIF column-field = 'DATETO'.
        APPEND |{ field } = '{ c_key_date }'| TO join-conditions.
      ELSE.
        " compounding: the same field of the view's tables
        READ TABLE sources INTO DATA(source) WITH KEY field = column-field.
        IF sy-subrc <> 0.
          reason = |key field { column-field } of { texts-name } is not in the view|.
          RETURN.
        ENDIF.
        APPEND |{ field } = { source-alias }.{ to_lower( column-field ) }| TO join-conditions.
      ENDIF.
    ENDLOOP.
    " the medium text, else the long, else the short one
    LOOP AT VALUE string_table( ( `TXTMD` ) ( `TXTLG` ) ( `TXTSH` ) ) INTO DATA(candidate).
      IF line_exists( texts-columns[ field = candidate key = abap_false ] ).
        text_field = candidate.
        RETURN.
      ENDIF.
    ENDLOOP.
    reason = |{ texts-name } has no text field|.
  ENDMETHOD.

  METHOD as_text.
    DATA(field) = |{ source }.{ to_lower( column-field ) }|.
    CASE column-datatype.
      WHEN 'CHAR'.
        result = field.
      WHEN 'NUMC' OR 'DATS' OR 'TIMS' OR 'CUKY' OR 'UNIT' OR 'LANG'.
        result = |cast( { field } as abap.char({ column-length }) )|.
    ENDCASE.
  ENDMETHOD.

  METHOD ddl_source.
    DATA(nl) = cl_abap_char_utilities=>newline.
    result = |@AbapCatalog.sqlViewName: '{ view_name }'| && nl &&
             |@AbapCatalog.compiler.compareFilter: true| && nl &&
             |@AccessControl.authorizationCheck: #NOT_REQUIRED| && nl &&
             |@EndUserText.label: '{ description( characteristic = characteristic
                                                  selection      = layout-selection ) }'| && nl &&
             |define view { ddl_name( view_name ) }| && nl &&
             |  as select from { to_lower( layout-tables-sids ) } as s| && nl &&
             joins_source( layout-joins ) &&
             |\{| && nl.
    LOOP AT layout-columns INTO DATA(column).
      result = result && COND string( WHEN sy-tabix = 1 THEN `  key ` ELSE |,{ nl }      | ) &&
               |{ column-expression } as { column-name }|.
    ENDLOOP.
    result = result && nl && |\}| && where_source( layout-filters ) && nl.
  ENDMETHOD.

  METHOD joins_source.
    DATA(nl) = cl_abap_char_utilities=>newline.
    LOOP AT joins INTO DATA(join).
      DATA(kind) = COND string( WHEN join-inner = abap_true THEN `inner join` ELSE `left outer join` ).
      LOOP AT join-conditions INTO DATA(condition).
        IF sy-tabix = 1.
          result = result && |    { kind } { to_lower( join-table ) } as { join-alias } on  { condition }| && nl.
        ELSE.
          result = result && |                                        and { condition }| && nl.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD where_source.
    LOOP AT filters INTO DATA(filter).
      result = result && cl_abap_char_utilities=>newline &&
               COND string( WHEN sy-tabix = 1 THEN |where { filter }| ELSE |  and { filter }| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD add_column.
    DATA(field) = |{ source }.{ to_lower( column-field ) }|.
    APPEND VALUE #( name       = name
                    expression = field
                    datatype   = column-datatype
                    length     = column-length
                    iobjnm     = iobjnm
                    navigation = navigation ) TO layout-columns.
    IF column-datatype <> 'NUMC'.
      RETURN.
    ENDIF.
    DATA(int_name) = |{ name }_INT|.
    IF strlen( int_name ) > 30.
      APPEND VALUE #( iobjnm = iobjnm reason = |no number of { name }: { int_name } is longer than 30 characters| )
        TO layout-notes.
      RETURN.
    ELSEIF line_exists( layout-columns[ name = int_name ] ).
      APPEND VALUE #( iobjnm = iobjnm reason = |no number of { name }: { int_name } is the name of another column| )
        TO layout-notes.
      RETURN.
    ENDIF.
    IF column-length <= 9.
      APPEND VALUE #( name = int_name expression = |cast( { field } as abap.int4 )| datatype = `INT4` length = 10
                      int_of = name ) TO layout-columns.
    ELSEIF column-length <= 18.
      APPEND VALUE #( name = int_name expression = |cast( { field } as abap.int8 )| datatype = `INT8` length = 19
                      int_of = name ) TO layout-columns.
    ELSE.
      APPEND VALUE #( name = int_name expression = |cast( { field } as abap.dec(31,0) )| datatype = `DEC` length = 31
                      int_of = name ) TO layout-columns.
    ENDIF.
  ENDMETHOD.

  METHOD view_column.
    " a namespace is /NAME/: everything up to the second slash
    result = field.
    IF strlen( field ) > 1 AND field(1) = '/'.
      FIND FIRST OCCURRENCE OF '/' IN SECTION OFFSET 1 OF field MATCH OFFSET DATA(slash).
      IF sy-subrc = 0.
        result = substring( val = field off = slash + 1 ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD placeholder.
    result = |{ c_placeholder_prefix }{ characteristic }|.
  ENDMETHOD.

  METHOD characteristic_of_placeholder.
    DATA(length) = strlen( c_placeholder_prefix ).
    IF strlen( table ) > length AND substring( val = table len = length ) = c_placeholder_prefix.
      result = substring( val = table off = length ).
    ENDIF.
  ENDMETHOD.

  METHOD ddl_name.
    result = |{ c_ddl_prefix }{ substring( val = view_name off = strlen( c_view_prefix ) ) }|.
  ENDMETHOD.

  METHOD description.
    " at most 49 characters up to the colon, so the description of every characteristic is a different one
    IF selection IS INITIAL.
      result = |BW characteristic { characteristic }: SID with active attributes|.
    ELSE.
      result = |BW characteristic { characteristic }: { selection_label( selection ) }|.
    ENDIF.
  ENDMETHOD.

  METHOD fact_description.
    IF selection IS INITIAL.
      result = |BW aDSO { provider }: facts with SIDs of compounding|.
    ELSE.
      result = |BW provider { provider }: facts of { selection_label( selection ) }|.
    ENDIF.
  ENDMETHOD.

  METHOD selection_text.
    result = zzxxmla1_cl_bw_selection=>selection_text( selection_of( fixed ) ).
  ENDMETHOD.

  METHOD selection_of.
    LOOP AT fixed INTO DATA(value).
      INSERT VALUE #( iobjnm = value-iobjnm
                      mode   = zzxxmla1_cl_bw_selection=>c_mode-filter
                      rows   = zzxxmla1_cl_bw_selection=>equals( value-value ) ) INTO TABLE result.
    ENDLOOP.
  ENDMETHOD.

  METHOD filter_selection.
    LOOP AT selection INTO DATA(characteristic) WHERE mode = zzxxmla1_cl_bw_selection=>c_mode-filter.
      INSERT characteristic INTO TABLE result.
    ENDLOOP.
  ENDMETHOD.

  METHOD selection_label.
    result = replace( val = replace( val = selection sub = `=` with = ` = ` occ = 0 ) sub = `;` with = `, ` occ = 0 ).
    result = replace( val = result sub = `'` with = `` occ = 0 ).
  ENDMETHOD.

  METHOD fact_placeholder.
    result = |{ c_fact_placeholder_prefix }{ provider }|.
  ENDMETHOD.

  METHOD provider_of_fact_placeholder.
    DATA(length) = strlen( c_fact_placeholder_prefix ).
    IF strlen( table ) > length AND substring( val = table len = length ) = c_fact_placeholder_prefix.
      result = substring( val = table off = length ).
    ENDIF.
  ENDMETHOD.

  METHOD existing_ddl_name.
    DATA(object) = CONV zzxxmla1_view-object_name( object_name ).
    SELECT SINGLE ddl_name FROM zzxxmla1_view
      WHERE kind = @kind AND object_name = @object AND selection = @selection
      INTO @DATA(registered).
    IF sy-subrc = 0.
      SELECT SINGLE ddlname FROM ddddlsrc WHERE ddlname = @registered INTO @result.
      IF sy-subrc = 0.
        RETURN.
      ENDIF.
      CLEAR result.
    ENDIF.
    IF selection IS INITIAL.
      result = ddl_of_description( description ).
    ENDIF.
  ENDMETHOD.

  METHOD ddl_of_description.
    " a numbered source sorts before one of the older name (ZZXXMLA1_C_<characteristic>)
    DATA(pattern) = |{ c_ddl_prefix }%|.
    SELECT t~ddlname FROM ddddlsrct AS t
      INNER JOIN ddddlsrc AS s ON s~ddlname = t~ddlname AND s~as4local = t~as4local
      WHERE t~ddtext = @description AND t~ddlname LIKE @pattern
      ORDER BY t~ddlname ASCENDING
      INTO TABLE @DATA(names).
    IF names IS NOT INITIAL.
      result = names[ 1 ]-ddlname.
    ENDIF.
  ENDMETHOD.

  METHOD view_selection.
    IF selection IS INITIAL.
      RETURN.
    ENDIF.
    DATA(basic) = tables( characteristic )-basic.
    LOOP AT compounding( basic ) INTO DATA(compounding).
      READ TABLE selection INTO DATA(value) WITH TABLE KEY iobjnm = compounding-iobjnm.
      IF sy-subrc = 0.
        INSERT value INTO TABLE result.
      ENDIF.
    ENDLOOP.
    READ TABLE selection INTO value WITH TABLE KEY iobjnm = characteristic.
    IF sy-subrc = 0 AND basic = characteristic.
      INSERT value INTO TABLE result.
    ENDIF.
  ENDMETHOD.

  METHOD compounding.
    SELECT c~iobjcmp, o~fieldnm FROM rsdiobjcmp AS c
      INNER JOIN rsdiobj AS o ON o~iobjnm = c~iobjcmp AND o~objvers = 'A'
      WHERE c~iobjnm = @basic AND c~objvers = 'A'
      ORDER BY c~posit ASCENDING
      INTO TABLE @DATA(rows).
    result = VALUE #( FOR row IN rows ( iobjnm = row-iobjcmp field = row-fieldnm ) ).
  ENDMETHOD.

  METHOD tables.
    DATA sids            TYPE rssidtab.
    DATA attributes      TYPE rschntab.
    DATA time_attributes TYPE rschttab.
    DATA texts           TYPE rstxttab.
    " a reference characteristic (0SOLD_TO -> 0CUSTOMER) has no tables of its own: they and their key field are the
    " basic characteristic's
    SELECT SINGLE chabasnm FROM rsdcha WHERE chanm = @characteristic AND objvers = 'A' INTO @result-basic.
    IF result-basic IS INITIAL.
      result-basic = characteristic.
    ENDIF.
    CALL FUNCTION 'RSD_CHKTAB_GET_FOR_CHA_BAS'
      EXPORTING
        i_chabasnm = result-basic
      IMPORTING
        e_chntab   = attributes
        e_chttab   = time_attributes
        e_txttab   = texts
        e_sidtab   = sids
      EXCEPTIONS
        name_error = 1
        OTHERS     = 2.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    SELECT SINGLE fieldnm FROM rsdiobj WHERE iobjnm = @result-basic AND objvers = 'A' INTO @result-key_field.
    " the key must be a column of each, else no view can join them
    result-sids = usable_table( table = sids key_field = result-key_field ).
    result-attributes = usable_table( table = attributes key_field = result-key_field ).
    result-time_attributes = usable_table( table = time_attributes key_field = result-key_field ).
    result-texts = usable_table( table = texts key_field = result-key_field ).
  ENDMETHOD.

  METHOD usable_table.
    IF table IS INITIAL OR key_field IS INITIAL.
      RETURN.
    ENDIF.
    SELECT SINGLE fieldname FROM dd03l
      WHERE tabname = @table AND as4local = 'A' AND fieldname = @key_field
      INTO @DATA(found).
    IF sy-subrc = 0.
      result = table.
    ENDIF.
  ENDMETHOD.

  METHOD metadata.
    result-characteristic = characteristic.
    result-tables = tables( characteristic ).
    IF result-tables-sids IS INITIAL.
      RETURN.
    ENDIF.
    result-sid_columns = table_columns( result-tables-sids ).
    result-attribute_columns = table_columns( result-tables-attributes ).
    result-time_attribute_columns = table_columns( result-tables-time_attributes ).
    result-texts = text_table( result-tables ).
    result-compounding = compounding( result-tables-basic ).
    " the attributes of the basic characteristic in BW's order; a characteristic among them has its own texts
    SELECT a~attrinm, a~attritp, o~fieldnm, o~iobjtp FROM rsdbchatr AS a
      INNER JOIN rsdiobj AS o ON o~iobjnm = a~attrinm AND o~objvers = 'A'
      WHERE a~chabasnm = @result-tables-basic AND a~objvers = 'A'
      ORDER BY a~posit ASCENDING
      INTO TABLE @DATA(attributes).
    LOOP AT attributes INTO DATA(attribute).
      APPEND VALUE #( iobjnm     = attribute-attrinm
                      field      = attribute-fieldnm
                      navigation = xsdbool( attribute-attritp = 'NAV' )
                      texts      = COND #( WHEN attribute-iobjtp = 'CHA' OR attribute-iobjtp = 'TIM'
                                           THEN text_table( tables( attribute-attrinm ) ) ) ) TO result-attributes.
    ENDLOOP.
  ENDMETHOD.

  METHOD text_table.
    IF tables-texts IS INITIAL.
      RETURN.
    ENDIF.
    result = VALUE #( name = tables-texts key_field = tables-key_field columns = table_columns( tables-texts ) ).
  ENDMETHOD.

  METHOD existing_view.
    DATA(text) = zzxxmla1_cl_bw_selection=>selection_text( view_selection( characteristic = characteristic
                                                                           selection      = selection ) ).
    result = view_of_ddl( existing_ddl_name( kind        = c_kind-characteristic
                                             object_name = characteristic
                                             selection   = text
                                             description = description( characteristic = characteristic
                                                                        selection      = text ) ) ).
  ENDMETHOD.

  METHOD view_of_ddl.
    IF ddl_name IS INITIAL.
      RETURN.
    ENDIF.
    TRY.
        ddl_handler( )->get_ddl_content_object_names( EXPORTING ddlname   = ddl_name
                                                                get_state = 'A'
                                                      IMPORTING viewname  = result ).
      CATCH cx_dd_ddl_read.
        CLEAR result.
    ENDTRY.
  ENDMETHOD.

  METHOD table_columns.
    IF table IS INITIAL.
      RETURN.
    ENDIF.
    SELECT fieldname, datatype, leng, keyflag FROM dd03l
      WHERE tabname = @table AND as4local = 'A' AND fieldname NOT LIKE '.%'
      ORDER BY position ASCENDING
      INTO TABLE @DATA(fields).
    LOOP AT fields INTO DATA(field).
      APPEND VALUE #( field    = field-fieldname
                      datatype = field-datatype
                      length   = field-leng
                      key      = xsdbool( field-keyflag = abap_true ) ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD view_name_for.
    IF ddl_name IS NOT INITIAL.
      TRY.
          ddl_handler( )->get_ddl_content_object_names( EXPORTING ddlname  = ddl_name
                                                                  get_state = 'A'
                                                        IMPORTING viewname = result ).
        CATCH cx_dd_ddl_read.
          CLEAR result.
      ENDTRY.
      IF number_of( name = result prefix = c_view_prefix ) > 0.
        RETURN.
      ENDIF.
    ENDIF.
    " the next number after the highest one in use by a database view or a DDL source
    DATA(highest) = 0.
    DATA(pattern) = |{ c_view_prefix }%|.
    SELECT tabname FROM dd02l WHERE tabname LIKE @pattern AND as4local = 'A' INTO TABLE @DATA(views).
    LOOP AT views INTO DATA(view).
      highest = nmax( val1 = highest val2 = number_of( name = view-tabname prefix = c_view_prefix ) ).
    ENDLOOP.
    pattern = |{ c_ddl_prefix }%|.
    SELECT ddlname FROM ddddlsrc WHERE ddlname LIKE @pattern INTO TABLE @DATA(sources).
    LOOP AT sources INTO DATA(source).
      highest = nmax( val1 = highest val2 = number_of( name = source-ddlname prefix = c_ddl_prefix ) ).
    ENDLOOP.
    LOOP AT used_numbers INTO DATA(used) WHERE table_line > highest.
      highest = used.
    ENDLOOP.
    highest = highest + 1.
    APPEND highest TO used_numbers.
    result = |{ c_view_prefix }{ highest WIDTH = 7 ALIGN = RIGHT PAD = '0' }|.
  ENDMETHOD.

  METHOD number_of.
    DATA(length) = strlen( prefix ).
    IF strlen( name ) = length + 7 AND substring( val = name len = length ) = prefix.
      DATA(digits) = substring( val = name off = length ).
      IF digits CO '0123456789'.
        result = digits.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD ddl_handler.
    IF handler IS NOT BOUND.
      handler = cl_dd_ddl_handler_factory=>create( ).
    ENDIF.
    result = handler.
  ENDMETHOD.

ENDCLASS.
