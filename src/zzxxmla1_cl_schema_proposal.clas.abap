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
"!   BW key; the text CHARACTERISTIC Text; each attribute and its text.
"! - its first Hierarchy, unnamed so that it is the dimension's default, is flat: All and one level of the
"!   characteristic, with the text as member property Text and every display attribute (and navigation attribute
"!   the provider does not switch on) as member properties, key and text;
"! - every navigation attribute the provider switches on is a flat Hierarchy CHARACTERISTIC__ATTRIBUTE of the
"!   dimension, as BW names it, its level named by the attribute, with its text as property Text. Nothing is nested
"!   that BW does not nest: no user hierarchies, no time hierarchy; BW's time characteristics (0CALMONTH, ...) are
"!   characteristics like the others. No dimension is a TimeDimension: the user marks one (the suggestions give the
"!   level types). A characteristic without SID table (0CALDAY) has no view and is not proposed;
"! - one Measure per key figure that sums, takes the minimum or the maximum, without exception aggregation and not
"!   non-cumulative, named by the key figure, captioned by its text, formatted by the decimals of its column; the
"!   first one is the default measure.
"! Identifiers are BW's technical names, so they are unique and never change; captions are texts. Whatever is not
"! proposed is a note with its reason; a level type the user may want when marking a dimension as time is a
"! suggestion. The proposal is written as schema XML and read as the reference reads it (ZZXXMLA1_CL_SCHEMA_DEF), so the
"! definition has the reference's defaults and the XML is toXML.
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
      BEGIN OF ty_proposal,
        schema      TYPE zzxxmla1_cl_schema_def=>ty_schema,
        xml         TYPE string,
        notes       TYPE zzxxmla1_cl_bw_provider=>ty_t_note,
        suggestions TYPE ty_t_suggestion,
      END OF ty_proposal.

    "! The proposal for a provider's metadata.
    METHODS propose
      IMPORTING provider      TYPE zzxxmla1_cl_bw_provider=>ty_provider
      RETURNING VALUE(result) TYPE ty_proposal
      RAISING   zzxxmla1_cx_xom.
    "! The level type of a standard BW time characteristic (0CALDAY TimeDays, ...), initial for any other.
    CLASS-METHODS time_level_type
      IMPORTING iobjnm        TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! The reference's data type of a column of a view: Integer for the integer types and for NUMC up to 9 digits (the
    "! views deliver NUMC as numbers), Numeric for the other numbers and longer NUMC, else String.
    CLASS-METHODS data_type
      IMPORTING column        TYPE zzxxmla1_cl_bw_provider=>ty_column
      RETURNING VALUE(result) TYPE string.
    "! The format string of a key figure's column: thousands separated, its decimals (at most 3).
    CLASS-METHODS format_string
      IMPORTING column        TYPE zzxxmla1_cl_bw_provider=>ty_column
      RETURNING VALUE(result) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_xml_attribute,
        name  TYPE string,
        value TYPE string,
      END OF ty_xml_attribute,
      ty_t_xml_attribute TYPE STANDARD TABLE OF ty_xml_attribute WITH EMPTY KEY.
    TYPES:
      "! a dimension of the cube: a shared one with its foreign key
      BEGIN OF ty_usage,
        name        TYPE string,
        caption     TYPE string,
        foreign_key TYPE string,
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

    DATA xml TYPE string.
    DATA depth TYPE i.
    DATA notes TYPE zzxxmla1_cl_bw_provider=>ty_t_note.
    DATA suggestions TYPE ty_t_suggestion.

    "! Writes the shared dimension of a characteristic; returns its name, initial if there is none.
    METHODS write_dimension
      IMPORTING kind           TYPE string
                characteristic TYPE zzxxmla1_cl_bw_provider=>ty_characteristic
      RETURNING VALUE(result)  TYPE string.
    "! Writes a DimensionAttribute of one column, not an attribute hierarchy.
    METHODS write_attribute
      IMPORTING name        TYPE string
                key_column  TYPE zzxxmla1_cl_bw_provider=>ty_column
                name_column TYPE zzxxmla1_cl_bw_provider=>ty_column OPTIONAL
                usage       TYPE string OPTIONAL.
    "! Writes a flat Hierarchy: All and one level, the level's text as property Text.
    METHODS open_hierarchy
      IMPORTING name           TYPE string OPTIONAL
                caption        TYPE string
                level          TYPE string
                attribute      TYPE string
                text_attribute TYPE string OPTIONAL.
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
    CLEAR: xml, depth, notes, suggestions.
    notes = provider-notes.
    DATA usages TYPE ty_t_usage.

    open( name = `Schema` attributes = VALUE #( ( name = `name` value = provider-name ) ) ).
    " the cube's dimensions in the provider's order
    LOOP AT provider-characteristics INTO DATA(characteristic).
      DATA(name) = write_dimension( kind = provider-kind characteristic = characteristic ).
      IF name IS NOT INITIAL.
        APPEND VALUE #( name = name caption = characteristic-text foreign_key = characteristic-fact_column-name )
          TO usages.
      ENDIF.
    ENDLOOP.
    write_cube( provider = provider usages = usages ).
    close( `Schema` ).

    result-schema = zzxxmla1_cl_schema_def=>parse( xml ).
    result-xml = zzxxmla1_cl_schema_def=>to_xml( result-schema ).
    result-notes = notes.
    result-suggestions = suggestions.
  ENDMETHOD.

  METHOD write_dimension.
    IF characteristic-has_sids = abap_false.
      note( iobjnm = characteristic-iobjnm reason = `no SID table, so no view` ).
      RETURN.
    ENDIF.
    result = characteristic-iobjnm.
    DATA(table) = COND string( WHEN characteristic-view IS NOT INITIAL THEN characteristic-view
                               ELSE zzxxmla1_cl_bw_view_gen=>placeholder( characteristic-basic ) ).
    open( name = `Dimension` attributes = VALUE #( ( name = `name` value = result )
                                                   ( name = `caption` value = characteristic-text )
                                                   ( name = `table` value = table ) ) ).

    " the key attribute: keyed by the SID on an InfoCube, by the value on an aDSO, named by the internal BW key
    DATA(key) = COND string( WHEN kind = zzxxmla1_cl_bw_provider=>c_kind-cube THEN |{ result } SID|
                             ELSE |{ result } Key| ).
    IF kind = zzxxmla1_cl_bw_provider=>c_kind-cube.
      write_attribute( name        = key
                       usage       = `Key`
                       key_column  = VALUE #( name = `SID` datatype = `INT4` length = 10 )
                       name_column = characteristic-key_column ).
    ELSE.
      write_attribute( name = key usage = `Key` key_column = characteristic-key_column ).
    ENDIF.
    suggest( dimension = result attribute = key iobjnm = characteristic-iobjnm column = characteristic-key_column ).
    DATA(text) = COND string( WHEN characteristic-text_column IS NOT INITIAL THEN |{ result } Text| ).
    IF text IS NOT INITIAL.
      write_attribute( name = text key_column = VALUE #( name = characteristic-text_column datatype = `CHAR` ) ).
    ENDIF.
    " a navigation attribute switched on is named as BW names it, <characteristic>__<attribute>; the others by the
    " attribute
    LOOP AT characteristic-attributes INTO DATA(attribute).
      DATA(name) = COND string( WHEN attribute-navigation = abap_true THEN |{ result }__{ attribute-iobjnm }|
                                ELSE attribute-iobjnm ).
      write_attribute( name = name key_column = attribute-column ).
      suggest( dimension = result attribute = name iobjnm = attribute-iobjnm column = attribute-column ).
      IF attribute-text_column IS NOT INITIAL.
        write_attribute( name = |{ name } Text| key_column = VALUE #( name = attribute-text_column datatype = `CHAR` ) ).
      ENDIF.
    ENDLOOP.

    " the characteristic: flat, the other attributes as properties
    open_hierarchy( caption = characteristic-text level = result attribute = key text_attribute = text ).
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
                      text_attribute = COND #( WHEN attribute-text_column IS NOT INITIAL THEN |{ name } Text| ) ).
      close_hierarchy( ).
    ENDLOOP.
    close( `Dimension` ).
  ENDMETHOD.

  METHOD write_attribute.
    open( name = `DimensionAttribute` attributes = VALUE #( ( name = `name` value = name )
                                                            ( name = `usage` value = usage )
                                                            ( name = `attributeHierarchyEnabled` value = `false` ) ) ).
    leaf( name = `KeyColumn` attributes = VALUE #( ( name = `dataType` value = data_type( key_column ) )
                                                   ( name = `columnName` value = key_column-name ) ) ).
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
                                               ( name = `sourceAttribute` value = attribute ) ) ).
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

  METHOD suggest.
    DATA(level_type) = time_level_type( iobjnm ).
    IF level_type IS INITIAL AND column-datatype = `DATS`.
      level_type = `TimeDays`.
    ENDIF.
    IF level_type IS NOT INITIAL.
      APPEND VALUE #( dimension = dimension attribute = attribute level_type = level_type ) TO suggestions.
    ENDIF.
  ENDMETHOD.

  METHOD write_cube.
    DATA(measures) = measures( provider-key_figures ).
    open( name = `Cube` attributes = VALUE #( ( name = `name` value = provider-name )
                                              ( name = `caption` value = provider-text )
                                              ( name = `defaultMeasure` value = VALUE #( measures[ 1 ]-name OPTIONAL ) ) ) ).
    leaf( name = `Table` attributes = VALUE #( ( name = `name` value = provider-fact_table ) ) ).
    LOOP AT usages INTO DATA(usage).
      leaf( name = `DimensionUsage` attributes = VALUE #( ( name = `name` value = usage-name )
                                                          ( name = `caption` value = usage-caption )
                                                          ( name = `source` value = usage-name )
                                                          ( name = `foreignKey` value = usage-foreign_key ) ) ).
    ENDLOOP.
    LOOP AT measures INTO DATA(measure).
      leaf( name = `Measure` attributes = VALUE #( ( name = `name` value = measure-name )
                                                   ( name = `caption` value = measure-caption )
                                                   ( name = `column` value = measure-column )
                                                   ( name = `aggregator` value = measure-aggregator )
                                                   ( name = `formatString` value = measure-format_string ) ) ).
    ENDLOOP.
    close( `Cube` ).
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
      WHEN `NUMC`.
        result = COND #( WHEN column-length <= 9 THEN `Integer` ELSE `Numeric` ).
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

ENDCLASS.
