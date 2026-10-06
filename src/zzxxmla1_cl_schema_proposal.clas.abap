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
"! The schema proposed for a BW InfoProvider (docs/schema-generator.md, The proposal), from the metadata
"! ZZXXMLA1_CL_BW_PROVIDER reads:
"! - one shared Dimension per characteristic on its generated view (ZZXXMLA1_CL_BW_VIEW_GEN; a view not generated yet
"!   is named by its DDL source, which acceptance replaces by the view), named by the characteristic's text, the same
"!   for InfoCubes and aDSOs and for BW's time characteristics (0CALMONTH, ...) as for any other: every dimension is
"!   joined to its view, none is built on the fact table's columns. The characteristic is the key attribute, named
"!   like the dimension: on an InfoCube keyed by the view's SID (the fact table's SID column is the foreign key) and
"!   named by the value, on an aDSO keyed by the value (the fact column). Every time-independent attribute is a further
"!   DimensionAttribute; each attribute is an attribute hierarchy, and there are no user hierarchies, because BW does
"!   not say which attributes nest in which order. A characteristic without SID table (0CALDAY) has no view and is not
"!   proposed. No dimension is a TimeDimension: the user marks one (the suggestions give the level types);
"! - one Measure per key figure that sums, takes the minimum or the maximum, without exception aggregation and not
"!   non-cumulative; the first one is the default measure.
"! Names are unique where the reference needs them to be: a repeated text gets the InfoObject in brackets. Whatever is not
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

        foreign_key TYPE string,

      END OF ty_usage,

      ty_t_usage TYPE STANDARD TABLE OF ty_usage WITH EMPTY KEY.

    TYPES:

      BEGIN OF ty_measure,

        name        TYPE string,

        column      TYPE string,

        aggregator  TYPE string,

      END OF ty_measure,

      ty_t_measure TYPE STANDARD TABLE OF ty_measure WITH EMPTY KEY.

    TYPES:

      "! a name in use, per scope: dimensions, the attributes of one dimension, measures

      BEGIN OF ty_used_name,

        scope TYPE string,

        name  TYPE string,

      END OF ty_used_name,

      ty_t_used_name TYPE STANDARD TABLE OF ty_used_name WITH EMPTY KEY.



    DATA xml TYPE string.

    DATA depth TYPE i.

    DATA notes TYPE zzxxmla1_cl_bw_provider=>ty_t_note.

    DATA suggestions TYPE ty_t_suggestion.

    DATA used_names TYPE ty_t_used_name.



    "! Writes the shared dimension of a characteristic; returns its name, initial if there is none.

    METHODS write_dimension

      IMPORTING kind           TYPE string

                characteristic TYPE zzxxmla1_cl_bw_provider=>ty_characteristic

      RETURNING VALUE(result)  TYPE string.

    METHODS write_cube

      IMPORTING provider TYPE zzxxmla1_cl_bw_provider=>ty_provider

                usages   TYPE ty_t_usage.

    "! The measures of the key figures; the others are notes.

    METHODS measures

      IMPORTING key_figures   TYPE zzxxmla1_cl_bw_provider=>ty_t_key_figure

      RETURNING VALUE(result) TYPE ty_t_measure.

    "! A name not used yet in the scope (case-insensitive): the text, else the text with the InfoObject in brackets.

    METHODS unique_name

      IMPORTING scope         TYPE string

                text          TYPE string

                iobjnm        TYPE string

      RETURNING VALUE(result) TYPE string.

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

    CLEAR: xml, depth, notes, suggestions, used_names.

    notes = provider-notes.

    DATA usages TYPE ty_t_usage.



    open( name = `Schema` attributes = VALUE #( ( name = `name` value = provider-name ) ) ).

    " the cube's dimensions in the provider's order

    LOOP AT provider-characteristics INTO DATA(characteristic).

      DATA(name) = write_dimension( kind = provider-kind characteristic = characteristic ).

      IF name IS NOT INITIAL.

        APPEND VALUE #( name = name foreign_key = characteristic-fact_column-name ) TO usages.

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

    result = unique_name( scope = `dimension` text = characteristic-text iobjnm = characteristic-iobjnm ).

    DELETE used_names WHERE scope = `attribute`.

    DATA(table) = COND string( WHEN characteristic-view IS NOT INITIAL THEN characteristic-view

                               ELSE zzxxmla1_cl_bw_view_gen=>placeholder( characteristic-iobjnm ) ).

    open( name = `Dimension` attributes = VALUE #( ( name = `name` value = result ) ( name = `table` value = table ) ) ).



    " the key attribute: the characteristic itself

    DATA(key_name) = unique_name( scope = `attribute` text = result iobjnm = characteristic-iobjnm ).

    open( name = `DimensionAttribute` attributes = VALUE #( ( name = `name` value = key_name )

                                                            ( name = `usage` value = `Key` ) ) ).

    IF kind = zzxxmla1_cl_bw_provider=>c_kind-cube.

      leaf( name = `KeyColumn` attributes = VALUE #( ( name = `dataType` value = `Integer` )

                                                     ( name = `columnName` value = `SID` ) ) ).

      leaf( name = `NameColumn` attributes = VALUE #( ( name = `dataType` value = data_type( characteristic-key_column ) )

                                                      ( name = `columnName` value = characteristic-key_column-name ) ) ).

    ELSE.

      leaf( name = `KeyColumn` attributes = VALUE #( ( name = `dataType` value = data_type( characteristic-key_column ) )

                                                     ( name = `columnName` value = characteristic-key_column-name ) ) ).

    ENDIF.

    close( `DimensionAttribute` ).

    DATA(level_type) = time_level_type( characteristic-iobjnm ).

    IF level_type IS INITIAL AND characteristic-key_column-datatype = `DATS`.

      level_type = `TimeDays`.

    ENDIF.

    IF level_type IS NOT INITIAL.

      APPEND VALUE #( dimension = result attribute = key_name level_type = level_type ) TO suggestions.

    ENDIF.



    LOOP AT characteristic-attributes INTO DATA(attribute).

      DATA(attribute_name) = unique_name( scope = `attribute` text = attribute-text iobjnm = attribute-iobjnm ).

      open( name = `DimensionAttribute` attributes = VALUE #( ( name = `name` value = attribute_name ) ) ).

      leaf( name = `KeyColumn` attributes = VALUE #( ( name = `dataType` value = data_type( attribute-column ) )

                                                     ( name = `columnName` value = attribute-column-name ) ) ).

      close( `DimensionAttribute` ).

      level_type = time_level_type( attribute-iobjnm ).

      IF level_type IS INITIAL AND attribute-column-datatype = `DATS`.

        level_type = `TimeDays`.

      ENDIF.

      IF level_type IS NOT INITIAL.

        APPEND VALUE #( dimension = result attribute = attribute_name level_type = level_type ) TO suggestions.

      ENDIF.

    ENDLOOP.

    close( `Dimension` ).

  ENDMETHOD.



  METHOD write_cube.

    DATA(measures) = measures( provider-key_figures ).

    open( name = `Cube` attributes = VALUE #( ( name = `name` value = provider-name )

                                              ( name = `caption` value = provider-text )

                                              ( name = `defaultMeasure` value = VALUE #( measures[ 1 ]-name OPTIONAL ) ) ) ).

    leaf( name = `Table` attributes = VALUE #( ( name = `name` value = provider-fact_table ) ) ).

    LOOP AT usages INTO DATA(usage).

      leaf( name = `DimensionUsage` attributes = VALUE #( ( name = `name` value = usage-name )

                                                          ( name = `source` value = usage-name )

                                                          ( name = `foreignKey` value = usage-foreign_key ) ) ).

    ENDLOOP.

    LOOP AT measures INTO DATA(measure).

      leaf( name = `Measure` attributes = VALUE #( ( name = `name` value = measure-name )

                                                   ( name = `column` value = measure-column )

                                                   ( name = `aggregator` value = measure-aggregator ) ) ).

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

        APPEND VALUE #( name       = unique_name( scope = `measure` text = key_figure-text iobjnm = key_figure-iobjnm )

                        column     = key_figure-fact_column-name

                        aggregator = to_lower( key_figure-aggregation ) ) TO result.

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



  METHOD unique_name.

    result = COND #( WHEN text IS NOT INITIAL THEN text ELSE iobjnm ).

    IF line_exists( used_names[ scope = scope name = to_upper( result ) ] ).

      result = |{ result } ({ iobjnm })|.

    ENDIF.

    APPEND VALUE #( scope = scope name = to_upper( result ) ) TO used_names.

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
