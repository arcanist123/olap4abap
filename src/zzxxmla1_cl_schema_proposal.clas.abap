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
"! The schema proposed for a BW InfoProvider, modelled as BW models it (docs/bw-schema-design-guide.md), from the
"! metadata ZZXXMLA1_CL_BW_PROVIDER reads:
"! - one shared Dimension per characteristic, named by the InfoObject and captioned by its text, on the view of its
"!   basic characteristic (ZZXXMLA1_CL_BW_VIEW_GEN; a view not generated yet is named by a placeholder, which
"!   acceptance replaces by the view); a reference characteristic is a dimension of its own on the view of the one it
"!   references. Its DimensionAttributes describe the view's columns, none is an attribute hierarchy: the key
"!   attribute CHARACTERISTIC SID (an InfoCube's, keyed by the view's SID, the fact table's SID column being the
"!   foreign key) or CHARACTERISTIC Key (an aDSO's, keyed by the value, the fact column), both named by the internal
"!   BW key; on an InfoCube the value as attribute CHARACTERISTIC Key too; the text CHARACTERISTIC Text; each
"!   attribute and its text. A compounded characteristic is keyed by the SID on an aDSO too (its fact view's,
"!   ZZXXMLA1_CL_BW_PROVIDER) and named by its compounding and key (K4/2024001) and ordered by these names, its key a member property Key
"!   (docs/bw-schema-design-guide.md, section 3.7);
"! - its first Hierarchy, unnamed so that it is the dimension's default, is flat: All and one level of the
"!   characteristic, with the text as member property Text and every display attribute (and navigation attribute
"!   the provider does not switch on) as member properties, key and text;
"! - every navigation attribute the provider switches on is a flat Hierarchy CHARACTERISTIC__ATTRIBUTE of the
"!   dimension, as BW names it, its level named by the attribute, with its text as property Text. Nothing is nested
"!   that BW does not nest: no user hierarchies, no time hierarchy; BW's time characteristics (0CALMONTH, ...) are
"!   characteristics like the others. No dimension is a TimeDimension but those the caller names (the fiscal defaults,
"!   ZZXXMLA1_CL_SCHEMA_DEFAULTS): every attribute and level of one has its suggested level type, TimeUndefined where
"!   there is none, as the UI marks one, and its usage is not restricted to members with facts. The user marks the
"!   others (the suggestions give the level types). A characteristic without SID table (0CALDAY) has no view and is
"!   not proposed;
"! - one Measure per key figure that sums, takes the minimum or the maximum, without exception aggregation and not
"!   non-cumulative, named by the key figure, captioned by its text, formatted by the decimals of its column; the
"!   first one is the default measure;
"! - a default DrillThroughAction, the columns of the rows a double click on a cell shows (with the cell's measure):
"!   per characteristic its value and its text, if it has one, named by the characteristic's text.
"! Identifiers are BW's technical names, so they are unique and never change; captions are texts. Whatever is not
"! proposed is a note with its reason; a level type the user may want when marking a dimension as time is a
"! suggestion. Every dimension of the cube shows only its members with facts (the annotation olap4abap.membersWithFacts
"! on its DimensionUsage, docs/mvp-scope.md, Members with facts decision): a characteristic is shared by many providers,
"! which use few of its values; the UI switches it per dimension. The proposal is written as schema XML and read as the reference reads it (ZZXXMLA1_CL_SCHEMA_DEF), so the
"! definition has the reference's defaults and the XML is toXML.
"! A provider read for a selection (docs/bw-schema-design-guide.md, section 3.8, ZZXXMLA1_CL_BW_SELECTION) gives a
"! cube with an annotation olap4abap.filter.CHARACTERISTIC or olap4abap.members.CHARACTERISTIC per restricted one,
"! whose value is its rows; the restricted one is a dimension with the members of its selection (on its view filtered
"! on it), and a characteristic whose compounding is all fixed to one value is named as one that is not compounded
"! (the provider reads it so: no name column). The schema builder proposes without a selection
"! (ZZXXMLA1_CL_SCHEMA_FIX applies one to a schema as an edit) but its defaults: the API reads the provider for them
"! (ZZXXMLA1_CL_SCHEMA_DEFAULTS, the fiscal year variant fixed to K4); the demo generators give their own.
"! A NUMC value is proposed as BW holds it (0042, typed String; docs/mvp-scope.md, NUMC decision); where the view has
"! its number too (COLUMN_INT) the proposal lists it, so the UI can switch a dimension to numbers (42).
"! Run (F9): prints the proposals for the FoodMart providers ZFMSALESA and ZFMSALES.
CLASS zzxxmla1_cl_schema_proposal DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    TYPES:
      "! the level type the UI pre-selects for an attribute when the user marks its dimension as time; the generator
      "! never marks one itself (a date is not always the time of the facts)
      BEGIN OF ty_suggestion,
        dimension  TYPE string,
        attribute  TYPE string,
        level_type TYPE string,
      END OF ty_suggestion,
      ty_t_suggestion TYPE STANDARD TABLE OF ty_suggestion WITH EMPTY KEY.
    TYPES:
      "! a NUMC column of a dimension's table and its number, which the UI may name in its place, with the number's
      "! data type
      BEGIN OF ty_int_column,
        table      TYPE string,
        column     TYPE string,
        int_column TYPE string,
        data_type  TYPE string,
      END OF ty_int_column,
      ty_t_int_column TYPE STANDARD TABLE OF ty_int_column WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_proposal,
        schema      TYPE zzxxmla1_cl_schema_def=>ty_schema,
        xml         TYPE string,
        notes       TYPE zzxxmla1_cl_bw_provider=>ty_t_note,
        suggestions TYPE ty_t_suggestion,
        int_columns TYPE ty_t_int_column,
      END OF ty_proposal.

    "! The proposal for a provider's metadata; time: the characteristics whose dimensions are time dimensions.
    METHODS propose
      IMPORTING provider      TYPE zzxxmla1_cl_bw_provider=>ty_provider
                !time         TYPE string_table OPTIONAL
      RETURNING VALUE(result) TYPE ty_proposal
      RAISING   zzxxmla1_cx_xom.
    "! The level type of a standard BW time characteristic (0CALDAY TimeDays, ...), initial for any other.
    CLASS-METHODS time_level_type
      IMPORTING iobjnm        TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! The reference's data type of a column of a view: Integer for the integer types, Numeric for the other numbers,
    "! else String (NUMC too: the views deliver it as BW holds it).
    CLASS-METHODS data_type
      IMPORTING column        TYPE zzxxmla1_cl_bw_provider=>ty_column
      RETURNING VALUE(result) TYPE string.
    "! The format string of a key figure's column: thousands separated, its decimals (at most 3).
    CLASS-METHODS format_string
      IMPORTING column        TYPE zzxxmla1_cl_bw_provider=>ty_column
      RETURNING VALUE(result) TYPE string.
    "! The table of a characteristic's dimension: its view, or the placeholder of its basic characteristic's view if
    "! that is not generated yet (accepting the schema generates it).
    CLASS-METHODS table_of
      IMPORTING characteristic TYPE zzxxmla1_cl_bw_provider=>ty_characteristic
      RETURNING VALUE(result)  TYPE string.
    "! The NUMC columns of a characteristic's table that have a number (its key and its attributes).
    CLASS-METHODS int_columns_of
      IMPORTING characteristic TYPE zzxxmla1_cl_bw_provider=>ty_characteristic
      RETURNING VALUE(result)  TYPE ty_t_int_column.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_xml_attribute,
        name  TYPE string,
        value TYPE string,
      END OF ty_xml_attribute,
      ty_t_xml_attribute TYPE STANDARD TABLE OF ty_xml_attribute WITH EMPTY KEY.
    TYPES:
      "! a dimension of the cube: a shared one with its foreign key; a time dimension shows all its members
      BEGIN OF ty_usage,
        name        TYPE string,
        caption     TYPE string,
        foreign_key TYPE string,
        time        TYPE abap_bool,
      END OF ty_usage,
      ty_t_usage TYPE STANDARD TABLE OF ty_usage WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_measure,
        name          TYPE string,
        caption       TYPE string,
        column        TYPE string,
        aggregator    TYPE string,
        format_string TYPE string,
      END OF ty_measure,
      ty_t_measure TYPE STANDARD TABLE OF ty_measure WITH EMPTY KEY.
    TYPES:
      "! a column of the default drill-through action: a column of a dimension's view, by its attribute
      BEGIN OF ty_drill_column,
        name      TYPE string,
        dimension TYPE string,
        attribute TYPE string,
      END OF ty_drill_column,
      ty_t_drill_column TYPE STANDARD TABLE OF ty_drill_column WITH EMPTY KEY.

    DATA xml TYPE string.
    DATA drill_columns TYPE ty_t_drill_column.
    DATA depth TYPE i.
    DATA notes TYPE zzxxmla1_cl_bw_provider=>ty_t_note.
    DATA suggestions TYPE ty_t_suggestion.
    DATA int_columns TYPE ty_t_int_column.
    "! the characteristics whose dimensions are time dimensions
    DATA time_dimensions TYPE string_table.
    "! the dimension being written is a time dimension: its attributes and levels have level types
    DATA in_time TYPE abap_bool.

    "! Writes the shared dimension of a characteristic; returns its name, initial if there is none.
    METHODS write_dimension
      IMPORTING kind           TYPE string
                characteristic TYPE zzxxmla1_cl_bw_provider=>ty_characteristic
      RETURNING VALUE(result)  TYPE string.
    "! Adds the key and the text of a characteristic to the default drill-through action, named by the
    "! characteristic's text (by the InfoObject if it has none or another characteristic has the same).
    METHODS add_drill_columns
      IMPORTING characteristic TYPE zzxxmla1_cl_bw_provider=>ty_characteristic
                key            TYPE string
                text           TYPE string.
    "! Writes the default drill-through action: the columns double-clicking a cell shows, with the cell's measure.
    METHODS write_drill_through.
    "! Writes a DimensionAttribute of one column, not an attribute hierarchy; in a time dimension with the level
    "! type of the characteristic it shows (iobjnm), TimeUndefined if it has none.
    METHODS write_attribute
      IMPORTING name            TYPE string
                key_column      TYPE zzxxmla1_cl_bw_provider=>ty_column
                name_column     TYPE zzxxmla1_cl_bw_provider=>ty_column OPTIONAL
                order_by_column TYPE zzxxmla1_cl_bw_provider=>ty_column OPTIONAL
                usage           TYPE string OPTIONAL
                iobjnm          TYPE string OPTIONAL.
    "! Writes a flat Hierarchy: All and one level, the level's text as property Text; in a time dimension the level
    "! has the level type of its attribute's characteristic (iobjnm, column).
    METHODS open_hierarchy
      IMPORTING name           TYPE string OPTIONAL
                caption        TYPE string
                level          TYPE string
                attribute      TYPE string
                text_attribute TYPE string OPTIONAL
                iobjnm         TYPE string OPTIONAL
                column         TYPE zzxxmla1_cl_bw_provider=>ty_column OPTIONAL.
    METHODS close_hierarchy.
    "! Writes a member property.
    METHODS property
      IMPORTING name      TYPE string
                caption   TYPE string
                attribute TYPE string.
    METHODS write_cube
      IMPORTING provider TYPE zzxxmla1_cl_bw_provider=>ty_provider
                usages   TYPE ty_t_usage.
    "! The measures of the key figures; the others are notes.
    METHODS measures
      IMPORTING key_figures   TYPE zzxxmla1_cl_bw_provider=>ty_t_key_figure
      RETURNING VALUE(result) TYPE ty_t_measure.
    "! The level type of a column of a characteristic: a standard time characteristic's, TimeDays for a date; initial
    "! for any other.
    CLASS-METHODS level_type
      IMPORTING iobjnm        TYPE string
                column        TYPE zzxxmla1_cl_bw_provider=>ty_column
      RETURNING VALUE(result) TYPE string.
    "! The level type of an attribute or level of the dimension being written: initial outside a time dimension, else
    "! the column's, TimeUndefined if it has none.
    METHODS time_level_type_of
      IMPORTING iobjnm        TYPE string
                column        TYPE zzxxmla1_cl_bw_provider=>ty_column
      RETURNING VALUE(result) TYPE string.
    "! Suggests the level type of an attribute: a standard time characteristic's, or TimeDays for a date.
    METHODS suggest
      IMPORTING dimension TYPE string
                attribute TYPE string
                iobjnm    TYPE string
                column    TYPE zzxxmla1_cl_bw_provider=>ty_column.
    METHODS open
      IMPORTING name       TYPE string
                attributes TYPE ty_t_xml_attribute OPTIONAL.
    METHODS close
      IMPORTING name TYPE string.
    "! An element without children.
    METHODS leaf
      IMPORTING name       TYPE string
                attributes TYPE ty_t_xml_attribute OPTIONAL.
    "! A start tag; attributes with an initial value are left out.
    METHODS tag
      IMPORTING name       TYPE string
                attributes TYPE ty_t_xml_attribute
                empty      TYPE abap_bool.
    METHODS note
      IMPORTING iobjnm TYPE csequence
                reason TYPE string.
ENDCLASS.



CLASS zzxxmla1_cl_schema_proposal IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    DATA(reader) = NEW zzxxmla1_cl_bw_provider( ).
    LOOP AT VALUE string_table( ( `ZFMSALESA` ) ( `ZFMSALES` ) ) INTO DATA(name).
      TRY.
          DATA(proposal) = propose( reader->read( name ) ).
          out->write( proposal-xml ).
          LOOP AT proposal-notes INTO DATA(item).
            out->write( |not proposed: { item-iobjnm }, { item-reason }| ).
          ENDLOOP.
          LOOP AT proposal-suggestions INTO DATA(suggestion).
            out->write( |time suggestion: { suggestion-dimension }.{ suggestion-attribute } { suggestion-level_type }| ).
          ENDLOOP.
        CATCH zzxxmla1_cx_bw_provider zzxxmla1_cx_xom INTO DATA(error).
          out->write( |{ name }: { error->get_text( ) }| ).
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

  METHOD propose.
    CLEAR: xml, depth, notes, suggestions, drill_columns, int_columns, in_time.
    notes = provider-notes.
    time_dimensions = time.
    DATA usages TYPE ty_t_usage.

    open( name = `Schema` attributes = VALUE #( ( name = `name` value = provider-name ) ) ).
    " the cube's dimensions in the provider's order; a fixed characteristic too, with one member
    LOOP AT provider-characteristics INTO DATA(characteristic).
      DATA(name) = write_dimension( kind = provider-kind characteristic = characteristic ).
      IF name IS NOT INITIAL.
        APPEND VALUE #( name        = name
                        caption     = characteristic-text
                        foreign_key = characteristic-fact_column-name
                        time        = xsdbool( line_exists( time_dimensions[ table_line = characteristic-iobjnm ] ) ) )
          TO usages.
      ENDIF.
    ENDLOOP.
    write_cube( provider = provider usages = usages ).
    close( `Schema` ).

    result-schema = zzxxmla1_cl_schema_def=>parse( xml ).
    result-xml = zzxxmla1_cl_schema_def=>to_xml( result-schema ).
    result-notes = notes.
    result-suggestions = suggestions.
    result-int_columns = int_columns.
  ENDMETHOD.

  METHOD write_dimension.
    IF characteristic-has_sids = abap_false.
      note( iobjnm = characteristic-iobjnm reason = `no SID table, so no view` ).
      RETURN.
    ENDIF.
    " a compounded characteristic joined by its value would count a fact once per compounding value
    DATA(compounded) = xsdbool( characteristic-name_column IS NOT INITIAL ).
    DATA(by_sid) = xsdbool( kind = zzxxmla1_cl_bw_provider=>c_kind-cube OR characteristic-fact_sid = abap_true ).
    IF compounded = abap_true AND by_sid = abap_false.
      note( iobjnm = characteristic-iobjnm reason = `compounded, and the facts have no SID of it` ).
      RETURN.
    ENDIF.
    result = characteristic-iobjnm.
    DATA(table) = table_of( characteristic ).
    in_time = xsdbool( line_exists( time_dimensions[ table_line = characteristic-iobjnm ] ) ).
    open( name = `Dimension` attributes = VALUE #( ( name = `name` value = result )
                                                   ( name = `caption` value = characteristic-text )
                                                   ( name = `table` value = table )
                                                   ( name  = `type`
                                                     value = COND #( WHEN in_time = abap_true THEN `TimeDimension` ) ) ) ).
    LOOP AT int_columns_of( characteristic ) INTO DATA(numeric).
      IF NOT line_exists( int_columns[ table = numeric-table column = numeric-column ] ).
        APPEND numeric TO int_columns.
      ENDIF.
    ENDLOOP.

    " the key attribute: keyed by the SID where the facts have it (an InfoCube's, an aDSO's compounded characteristic),
    " else by the value; named by the internal BW key, a compounded one by its compounding and its key
    DATA(key) = COND string( WHEN by_sid = abap_true THEN |{ result } SID| ELSE |{ result } Key| ).
    " the value as an attribute of its own when keyed by the SID: the drill-through reads a column by its attribute
    DATA(value) = |{ result } Key|.
    IF by_sid = abap_true.
      write_attribute( name        = key
                       usage       = `Key`
                       iobjnm      = characteristic-iobjnm
                       key_column  = VALUE #( name = `SID` datatype = `INT4` length = 10 )
                       name_column = COND #( WHEN compounded = abap_true THEN characteristic-name_column
                                             ELSE characteristic-key_column )
                       " a compounded one in the order of its names: the SIDs are in the order BW made them
                       order_by_column = COND #( WHEN compounded = abap_true THEN characteristic-name_column ) ).
      write_attribute( name = value key_column = characteristic-key_column ).
    ELSE.
      write_attribute( name = key usage = `Key` key_column = characteristic-key_column iobjnm = characteristic-iobjnm ).
    ENDIF.
    suggest( dimension = result attribute = key iobjnm = characteristic-iobjnm column = characteristic-key_column ).
    DATA(text) = COND string( WHEN characteristic-text_column IS NOT INITIAL THEN |{ result } Text| ).
    IF text IS NOT INITIAL.
      write_attribute( name = text key_column = VALUE #( name = characteristic-text_column datatype = `CHAR` ) ).
    ENDIF.
    add_drill_columns( characteristic = characteristic key = value text = text ).
    " a navigation attribute switched on is named as BW names it, <characteristic>__<attribute>; the others by the
    " attribute
    LOOP AT characteristic-attributes INTO DATA(attribute).
      DATA(name) = COND string( WHEN attribute-navigation = abap_true THEN |{ result }__{ attribute-iobjnm }|
                                ELSE attribute-iobjnm ).
      write_attribute( name = name key_column = attribute-column iobjnm = attribute-iobjnm ).
      suggest( dimension = result attribute = name iobjnm = attribute-iobjnm column = attribute-column ).
      IF attribute-text_column IS NOT INITIAL.
        write_attribute( name = |{ name } Text| key_column = VALUE #( name = attribute-text_column datatype = `CHAR` ) ).
      ENDIF.
    ENDLOOP.

    " the characteristic: flat, the other attributes as properties
    open_hierarchy( caption        = characteristic-text
                    level          = result
                    attribute      = key
                    text_attribute = text
                    iobjnm         = characteristic-iobjnm
                    column         = characteristic-key_column ).
    IF compounded = abap_true.
      property( name = `Key` caption = |{ characteristic-text } (Key)| attribute = value ).
    ENDIF.
    LOOP AT characteristic-attributes INTO attribute WHERE navigation = abap_false.
      property( name = attribute-iobjnm caption = attribute-text attribute = attribute-iobjnm ).
      IF attribute-text_column IS NOT INITIAL.
        property( name      = |{ attribute-iobjnm } Text|
                  caption   = |{ attribute-text } (Text)|
                  attribute = |{ attribute-iobjnm } Text| ).
      ENDIF.
    ENDLOOP.
    close_hierarchy( ).
    " each navigation attribute switched on: a flat hierarchy of its own
    LOOP AT characteristic-attributes INTO attribute WHERE navigation = abap_true.
      name = |{ result }__{ attribute-iobjnm }|.
      open_hierarchy( name           = name
                      caption        = attribute-text
                      level          = attribute-iobjnm
                      attribute      = name
                      text_attribute = COND #( WHEN attribute-text_column IS NOT INITIAL THEN |{ name } Text| )
                      iobjnm         = attribute-iobjnm
                      column         = attribute-column ).
      close_hierarchy( ).
    ENDLOOP.
    close( `Dimension` ).
    in_time = abap_false.
  ENDMETHOD.

  METHOD write_attribute.
    open( name = `DimensionAttribute` attributes = VALUE #( ( name = `name` value = name )
                                                            ( name = `usage` value = usage )
                                                            ( name  = `levelType`
                                                              value = time_level_type_of( iobjnm = iobjnm
                                                                                          column = key_column ) )
                                                            ( name = `attributeHierarchyEnabled` value = `false` ) ) ).
    leaf( name = `KeyColumn` attributes = VALUE #( ( name = `dataType` value = data_type( key_column ) )
                                                   ( name = `columnName` value = key_column-name ) ) ).
    IF order_by_column IS NOT INITIAL.
      leaf( name = `OrderByColumn` attributes = VALUE #( ( name = `dataType` value = data_type( order_by_column ) )
                                                         ( name = `columnName` value = order_by_column-name ) ) ).
    ENDIF.
    IF name_column IS NOT INITIAL.
      leaf( name = `NameColumn` attributes = VALUE #( ( name = `dataType` value = data_type( name_column ) )
                                                      ( name = `columnName` value = name_column-name ) ) ).
    ENDIF.
    close( `DimensionAttribute` ).
  ENDMETHOD.

  METHOD open_hierarchy.
    open( name = `Hierarchy` attributes = VALUE #( ( name = `name` value = name )
                                                   ( name = `caption` value = caption )
                                                   ( name = `hasAll` value = `true` )
                                                   ( name = `allMemberName` value = |All { caption }| ) ) ).
    open( name = `Level` attributes = VALUE #( ( name = `name` value = level )
                                               ( name = `caption` value = caption )
                                               ( name = `uniqueMembers` value = `true` )
                                               ( name = `sourceAttribute` value = attribute )
                                               ( name  = `levelType`
                                                 value = time_level_type_of( iobjnm = iobjnm column = column ) ) ) ).
    IF text_attribute IS NOT INITIAL.
      property( name = `Text` caption = |{ caption } (Text)| attribute = text_attribute ).
    ENDIF.
  ENDMETHOD.

  METHOD close_hierarchy.
    close( `Level` ).
    close( `Hierarchy` ).
  ENDMETHOD.

  METHOD property.
    leaf( name = `Property` attributes = VALUE #( ( name = `name` value = name )
                                                  ( name = `caption` value = caption )
                                                  ( name = `sourceAttribute` value = attribute ) ) ).
  ENDMETHOD.

  METHOD level_type.
    result = time_level_type( iobjnm ).
    IF result IS INITIAL AND column-datatype = `DATS`.
      result = `TimeDays`.
    ENDIF.
  ENDMETHOD.

  METHOD time_level_type_of.
    IF in_time = abap_false.
      RETURN.
    ENDIF.
    result = level_type( iobjnm = iobjnm column = column ).
    IF result IS INITIAL.
      result = `TimeUndefined`.
    ENDIF.
  ENDMETHOD.

  METHOD suggest.
    DATA(level_type) = level_type( iobjnm = iobjnm column = column ).
    IF level_type IS NOT INITIAL.
      APPEND VALUE #( dimension = dimension attribute = attribute level_type = level_type ) TO suggestions.
    ENDIF.
  ENDMETHOD.

  METHOD write_cube.
    DATA(measures) = measures( provider-key_figures ).
    open( name = `Cube` attributes = VALUE #( ( name = `name` value = provider-name )
                                              ( name = `caption` value = provider-text )
                                              ( name = `defaultMeasure` value = VALUE #( measures[ 1 ]-name OPTIONAL ) ) ) ).
    IF provider-selection IS NOT INITIAL.
      open( `Annotations` ).
      LOOP AT provider-selection INTO DATA(restricted).
        DATA(name) = zzxxmla1_cl_bw_selection=>annotation_name( characteristic = restricted-iobjnm
                                                                mode           = restricted-mode ).
        xml = xml && repeat( val = ` ` occ = 2 * depth )
                  && |<Annotation name="{ escape( val = name format = cl_abap_format=>e_xml_attr ) }">|
                  && |{ escape( val    = zzxxmla1_cl_bw_selection=>rows_text( restricted-rows )
                                format = cl_abap_format=>e_xml_text ) }</Annotation>|
                  && cl_abap_char_utilities=>newline.
      ENDLOOP.
      close( `Annotations` ).
    ENDIF.
    leaf( name = `Table` attributes = VALUE #( ( name = `name` value = provider-fact_table ) ) ).
    LOOP AT usages INTO DATA(usage).
      open( name = `DimensionUsage` attributes = VALUE #( ( name = `name` value = usage-name )
                                                          ( name = `caption` value = usage-caption )
                                                          ( name = `source` value = usage-name )
                                                          ( name = `foreignKey` value = usage-foreign_key ) ) ).
      " not on a time dimension: the server does not support it there
      IF usage-time = abap_false.
        open( `Annotations` ).
        xml = xml && repeat( val = ` ` occ = 2 * depth )
                  && |<Annotation name="{ zzxxmla1_cl_schema=>c_members_with_facts }">true</Annotation>|
                  && cl_abap_char_utilities=>newline.
        close( `Annotations` ).
      ENDIF.
      close( `DimensionUsage` ).
    ENDLOOP.
    LOOP AT measures INTO DATA(measure).
      leaf( name = `Measure` attributes = VALUE #( ( name = `name` value = measure-name )
                                                   ( name = `caption` value = measure-caption )
                                                   ( name = `column` value = measure-column )
                                                   ( name = `aggregator` value = measure-aggregator )
                                                   ( name = `formatString` value = measure-format_string ) ) ).
    ENDLOOP.
    write_drill_through( ).
    close( `Cube` ).
  ENDMETHOD.

  METHOD add_drill_columns.
    DATA(name) = COND string( WHEN characteristic-text IS NOT INITIAL THEN characteristic-text
                              ELSE characteristic-iobjnm ).
    IF line_exists( drill_columns[ name = name ] ).
      name = characteristic-iobjnm.
    ENDIF.
    APPEND VALUE #( name = name dimension = characteristic-iobjnm attribute = key ) TO drill_columns.
    IF text IS NOT INITIAL.
      APPEND VALUE #( name = |{ name } (Text)| dimension = characteristic-iobjnm attribute = text ) TO drill_columns.
    ENDIF.
  ENDMETHOD.

  METHOD write_drill_through.
    IF drill_columns IS INITIAL.
      RETURN.
    ENDIF.
    open( name = `DrillThroughAction` attributes = VALUE #( ( name = `name` value = `Details` )
                                                            ( name = `default` value = `true` ) ) ).
    LOOP AT drill_columns INTO DATA(column).
      leaf( name = `DrillThroughAttribute` attributes = VALUE #( ( name = `name` value = column-name )
                                                                 ( name = `dimension` value = column-dimension )
                                                                 ( name = `sourceAttribute` value = column-attribute ) ) ).
    ENDLOOP.
    close( `DrillThroughAction` ).
  ENDMETHOD.

  METHOD measures.
    LOOP AT key_figures INTO DATA(key_figure).
      IF key_figure-non_cumulative = abap_true.
        note( iobjnm = key_figure-iobjnm reason = `non-cumulative key figure` ).
      ELSEIF key_figure-exception_aggregation <> key_figure-aggregation.
        note( iobjnm = key_figure-iobjnm reason = |exception aggregation { key_figure-exception_aggregation }| ).
      ELSEIF key_figure-aggregation <> `SUM` AND key_figure-aggregation <> `MIN` AND key_figure-aggregation <> `MAX`.
        note( iobjnm = key_figure-iobjnm reason = |aggregation { key_figure-aggregation }| ).
      ELSE.
        APPEND VALUE #( name          = key_figure-iobjnm
                        caption       = key_figure-text
                        column        = key_figure-fact_column-name
                        aggregator    = to_lower( key_figure-aggregation )
                        format_string = format_string( key_figure-fact_column ) ) TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD time_level_type.
    result = SWITCH #( iobjnm
                       WHEN `0CALDAY`     THEN `TimeDays`
                       WHEN `0CALWEEK`    THEN `TimeWeeks`
                       WHEN `0CALMONTH`   THEN `TimeMonths`
                       WHEN `0CALQUARTER` THEN `TimeQuarters`
                       WHEN `0CALYEAR`    THEN `TimeYears`
                       WHEN `0FISCPER`    THEN `TimeMonths`
                       WHEN `0FISCYEAR`   THEN `TimeYears` ).
  ENDMETHOD.

  METHOD data_type.
    CASE column-datatype.
      WHEN `INT1` OR `INT2` OR `INT4` OR `INT8`.
        result = `Integer`.
      WHEN `DEC` OR `CURR` OR `QUAN` OR `FLTP` OR `D16D` OR `D34D` OR `D16N` OR `D34N` OR `DF16_DEC` OR `DF34_DEC`.
        result = `Numeric`.
      WHEN OTHERS.
        result = `String`.
    ENDCASE.
  ENDMETHOD.

  METHOD format_string.
    DATA(decimals) = COND i( WHEN column-datatype CP 'INT*' THEN 0 ELSE nmin( val1 = column-decimals val2 = 3 ) ).
    result = COND #( WHEN decimals = 0 THEN `#,##0` ELSE |#,##0.{ repeat( val = `0` occ = decimals ) }| ).
  ENDMETHOD.

  METHOD open.
    tag( name = name attributes = attributes empty = abap_false ).
    depth = depth + 1.
  ENDMETHOD.

  METHOD close.
    depth = depth - 1.
    xml = xml && repeat( val = ` ` occ = 2 * depth ) && |</{ name }>| && cl_abap_char_utilities=>newline.
  ENDMETHOD.

  METHOD leaf.
    tag( name = name attributes = attributes empty = abap_true ).
  ENDMETHOD.

  METHOD tag.
    xml = xml && repeat( val = ` ` occ = 2 * depth ) && |<{ name }|.
    LOOP AT attributes INTO DATA(attribute) WHERE value IS NOT INITIAL.
      xml = xml && | { attribute-name }="{ escape( val = attribute-value format = cl_abap_format=>e_xml_attr ) }"|.
    ENDLOOP.
    xml = xml && COND string( WHEN empty = abap_true THEN `/>` ELSE `>` ) && cl_abap_char_utilities=>newline.
  ENDMETHOD.

  METHOD note.
    APPEND VALUE #( iobjnm = iobjnm reason = reason ) TO notes.
  ENDMETHOD.

  METHOD table_of.
    result = COND #( WHEN characteristic-view IS NOT INITIAL THEN characteristic-view
                     ELSE zzxxmla1_cl_bw_view_gen=>placeholder( characteristic-basic ) ).
  ENDMETHOD.

  METHOD int_columns_of.
    DATA(table) = table_of( characteristic ).
    DATA(columns) = VALUE zzxxmla1_cl_bw_provider=>ty_t_attribute(
      ( column = characteristic-key_column int_column = characteristic-key_int_column )
      ( LINES OF characteristic-attributes ) ).
    LOOP AT columns INTO DATA(column) WHERE int_column IS NOT INITIAL.
      IF NOT line_exists( result[ column = column-column-name ] ).
        APPEND VALUE #( table      = table
                        column     = column-column-name
                        int_column = column-int_column-name
                        data_type  = data_type( column-int_column ) ) TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
