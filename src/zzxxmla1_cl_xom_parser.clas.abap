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
"! Reads the children and attributes of one XML element as the generated SchemaDef constructors read them: the port
"! of eigenbase-xom's DOMElementParser over an iXML element, with the behaviour of its W3CDOMWrapper (JAXP parser).
"! The element children are consumed in document order, one cursor per element: get_element takes the next child if
"! its class matches, get_array the run of next children that match; whatever does not match where it is expected is
"! skipped silently, as in the reference (a Dimension after the Measures of a cube is never read). The class of a child
"! is its tag with the first letter in upper case (ElementDef.getElementClass); a match is a tag among the classes
"! assignable to the expected one, which the caller lists. An empty attribute is no attribute (getAttribute returns
"! null for ""), and text is all character data below the element without comments, trimmed as String.trim does.
CLASS zzxxmla1_cl_xom_parser DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_t_element TYPE STANDARD TABLE OF REF TO if_ixml_element WITH EMPTY KEY.

    "! Parses an XML document (XOMUtil.createDefaultParser( ).parse) and returns its root element.
    CLASS-METHODS parse_document
      IMPORTING xml           TYPE string
      RETURNING VALUE(result) TYPE REF TO if_ixml_element
      RAISING   zzxxmla1_cx_xom.
    "! The class an element stands for: its tag with the first letter in upper case (XOMUtil.capitalize).
    CLASS-METHODS class_name
      IMPORTING element       TYPE REF TO if_ixml_element
      RETURNING VALUE(result) TYPE string.

    METHODS constructor
      IMPORTING element TYPE REF TO if_ixml_element.
    "! getAttribute for a String: the value, else the default; initial is null. The value must be one of values if
    "! they are given; required without value nor default is an error.
    METHODS get_string
      IMPORTING name          TYPE string
                !default      TYPE string OPTIONAL
                !values       TYPE string_table OPTIONAL
                required      TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_xom.
    "! getAttribute for a Boolean (new Boolean( value )): true for "true" in any case, false for anything else,
    "! abap_undefined for null.
    METHODS get_boolean
      IMPORTING name          TYPE string
                !default      TYPE string OPTIONAL
                required      TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(result) TYPE abap_bool
      RAISING   zzxxmla1_cx_xom.
    "! getAttribute for an Integer or a Long (java_type Integer or Long): the number as Java writes it ("+0012" is
    "! 12), initial for null; a value that is not a number of that range is an error.
    METHODS get_number
      IMPORTING name          TYPE string
                java_type     TYPE string
                !default      TYPE string OPTIONAL
                required      TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_xom.
    "! getElement: the next child if it is of one of the classes, else none; java_class is the expected class for
    "! the message (e.g. olap4abap.SchemaDef$RelationOrJoin). Without further children it returns none even if
    "! the element is required; a required element of another class is an error.
    METHODS get_element
      IMPORTING classes       TYPE string_table
                java_class    TYPE string
                required      TYPE abap_bool
      RETURNING VALUE(result) TYPE REF TO if_ixml_element
      RAISING   zzxxmla1_cx_xom.
    "! getArray: the next children as long as they are of one of the classes; min and max (0: no limit) are checked.
    METHODS get_array
      IMPORTING classes       TYPE string_table
                java_class    TYPE string
                min           TYPE i
                max           TYPE i
      RETURNING VALUE(result) TYPE ty_t_element
      RAISING   zzxxmla1_cx_xom.
    "! getText: the text of the element, trimmed.
    METHODS get_text
      RETURNING VALUE(result) TYPE string.
    "! getString of a String element (e.g. DataSourcesConfig's <DataSourceName>): the trimmed text of the next child if
    "! its tag is the name in any case, else initial (null); required and another child or none is an error.
    METHODS get_string_element
      IMPORTING name          TYPE string
                required      TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_xom.

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA element  TYPE REF TO if_ixml_element.
    DATA children TYPE ty_t_element.
    "! position of the current child (DOMElementParser.currentChild) in children
    DATA current  TYPE i VALUE 1.

    "! getAttribute up to the conversion: the value or the default, checked against the legal values.
    METHODS get_attribute
      IMPORTING name          TYPE string
                !default      TYPE string
                !values       TYPE string_table OPTIONAL
                required      TYPE abap_bool
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_xom.
    METHODS current_matches
      IMPORTING classes       TYPE string_table
      RETURNING VALUE(result) TYPE abap_bool.
    CLASS-METHODS append_text
      IMPORTING node TYPE REF TO if_ixml_node
      CHANGING  text TYPE string.
    "! String.trim: without the leading and trailing characters up to U+0020.
    CLASS-METHODS trim
      IMPORTING text          TYPE string
      RETURNING VALUE(result) TYPE string.
ENDCLASS.



CLASS zzxxmla1_cl_xom_parser IMPLEMENTATION.

  METHOD parse_document.
    DATA(ixml) = cl_ixml=>create( ).
    DATA(stream_factory) = ixml->create_stream_factory( ).
    DATA(document) = ixml->create_document( ).
    DATA(parser) = ixml->create_parser( stream_factory = stream_factory
                                        istream        = stream_factory->create_istream_string( xml )
                                        document       = document ).
    " keep text as it is: the definition trims it itself, and whitespace inside mixed text must stay
    parser->set_normalizing( abap_false ).
    IF parser->parse( ) <> 0 OR document->get_root_element( ) IS NOT BOUND.
      DATA(error) = parser->get_error( index = 0 ).
      RAISE EXCEPTION TYPE zzxxmla1_cx_xom EXPORTING error_message = COND #(
        WHEN error IS BOUND
        THEN |XML parse error at line { error->get_line( ) }, column { error->get_column( ) }: { error->get_reason( ) }|
        ELSE `XML parse error: no root element` ).
    ENDIF.
    result = document->get_root_element( ).
  ENDMETHOD.

  METHOD class_name.
    DATA(tag) = element->get_name( ).
    result = to_upper( substring( val = tag len = 1 ) ) && substring( val = tag off = 1 ).
  ENDMETHOD.

  METHOD constructor.
    me->element = element.
    DATA(child) = element->get_first_child( ).
    WHILE child IS BOUND.
      IF child->get_type( ) = if_ixml_node=>co_node_element.
        APPEND CAST if_ixml_element( child ) TO children.
      ENDIF.
      child = child->get_next( ).
    ENDWHILE.
  ENDMETHOD.

  METHOD get_attribute.
    result = element->get_attribute( name ).
    IF result IS INITIAL.
      result = default.
    ENDIF.
    IF result IS INITIAL.
      IF required = abap_true.
        RAISE EXCEPTION TYPE zzxxmla1_cx_xom
          EXPORTING error_message = |Attribute '{ name }' is unset and has no default value.|.
      ENDIF.
      RETURN.
    ENDIF.
    IF values IS NOT INITIAL AND NOT line_exists( values[ table_line = result ] ).
      RAISE EXCEPTION TYPE zzxxmla1_cx_xom EXPORTING error_message =
        |Value '{ result }' of attribute '{ name }' has illegal value '{ result }'.  | &&
        |Legal values: \{{ concat_lines_of( table = values sep = `, ` ) }\}|.
    ENDIF.
  ENDMETHOD.

  METHOD get_string.
    result = get_attribute( name = name default = default values = values required = required ).
  ENDMETHOD.

  METHOD get_boolean.
    DATA(value) = get_attribute( name = name default = default required = required ).
    result = COND #( WHEN value IS INITIAL THEN abap_undefined
                     WHEN to_lower( value ) = `true` THEN abap_true
                     ELSE abap_false ).
  ENDMETHOD.

  METHOD get_number.
    DATA(value) = get_attribute( name = name default = default required = required ).
    IF value IS INITIAL.
      RETURN.
    ENDIF.
    " Integer.parseInt / Long.parseLong: an optional sign and decimal digits within the range of the type
    DATA(digits) = COND string( WHEN value(1) CA `+-` THEN substring( val = value off = 1 ) ELSE value ).
    DATA(valid) = xsdbool( digits IS NOT INITIAL AND matches( val = digits regex = `[0-9]+` ) ).
    IF valid = abap_true.
      DATA(number) = VALUE decfloat34( ).
      number = digits.
      IF value(1) = `-`.
        number = - number.
      ENDIF.
      IF java_type = `Integer`.
        valid = xsdbool( number BETWEEN -2147483648 AND 2147483647 ).
      ELSE.
        valid = xsdbool( number BETWEEN -9223372036854775808 AND 9223372036854775807 ).
      ENDIF.
    ENDIF.
    IF valid = abap_false.
      " the constructor's NumberFormatException comes wrapped in an InvocationTargetException without message
      RAISE EXCEPTION TYPE zzxxmla1_cx_xom
        EXPORTING error_message = |Unable to construct a java.lang.{ java_type } from value "{ value }": null|.
    ENDIF.
    result = |{ CONV int8( number ) }|.
  ENDMETHOD.

  METHOD current_matches.
    DATA(name) = class_name( children[ current ] ).
    result = xsdbool( line_exists( classes[ table_line = name ] ) ).
  ENDMETHOD.

  METHOD get_element.
    IF current > lines( children ).
      RETURN.
    ENDIF.
    IF current_matches( classes ) = abap_false.
      IF required = abap_true.
        RAISE EXCEPTION TYPE zzxxmla1_cx_xom EXPORTING error_message =
          |element <{ children[ current ]->get_name( ) }> is not of expected type { java_class }|.
      ENDIF.
      RETURN.
    ENDIF.
    result = children[ current ].
    current = current + 1.
  ENDMETHOD.

  METHOD get_array.
    WHILE current <= lines( children ) AND current_matches( classes ) = abap_true.
      APPEND children[ current ] TO result.
      current = current + 1.
    ENDWHILE.
    IF min > 0 AND lines( result ) < min.
      RAISE EXCEPTION TYPE zzxxmla1_cx_xom
        EXPORTING error_message = |Expecting at least { min } <{ java_class }> but found { lines( result ) }|.
    ENDIF.
    IF max > 0 AND lines( result ) > max.
      RAISE EXCEPTION TYPE zzxxmla1_cx_xom
        EXPORTING error_message = |Expecting at most { max } <{ java_class }> but found { lines( result ) }|.
    ENDIF.
  ENDMETHOD.

  METHOD get_text.
    append_text( EXPORTING node = element CHANGING text = result ).
    result = trim( result ).
  ENDMETHOD.

  METHOD get_string_element.
    " requiredName / optionalName: the tag matches in any case
    IF current > lines( children ).
      IF required = abap_true.
        RAISE EXCEPTION TYPE zzxxmla1_cx_xom EXPORTING error_message = |Expected <{ name }> but found nothing.|.
      ENDIF.
      RETURN.
    ENDIF.
    DATA(child) = children[ current ].
    IF to_upper( child->get_name( ) ) <> to_upper( name ).
      IF required = abap_true.
        RAISE EXCEPTION TYPE zzxxmla1_cx_xom
          EXPORTING error_message = |Expected <{ name }> but found <{ child->get_name( ) }>|.
      ENDIF.
      RETURN.
    ENDIF.
    append_text( EXPORTING node = child CHANGING text = result ).
    result = trim( result ).
    current = current + 1.
  ENDMETHOD.

  METHOD append_text.
    " W3CDOMWrapper.appendNodeText: character data (text and CDATA, not comments), elements recursively
    CASE node->get_type( ).
      WHEN if_ixml_node=>co_node_text OR if_ixml_node=>co_node_cdata_section.
        text = text && node->get_value( ).
      WHEN if_ixml_node=>co_node_element.
        DATA(child) = node->get_first_child( ).
        WHILE child IS BOUND.
          append_text( EXPORTING node = child CHANGING text = text ).
          child = child->get_next( ).
        ENDWHILE.
    ENDCASE.
  ENDMETHOD.

  METHOD trim.
    DATA(first) = 0.
    DATA(last) = strlen( text ) - 1.
    WHILE first <= last AND cl_abap_conv_out_ce=>uccpi( substring( val = text off = first len = 1 ) ) <= 32.
      first = first + 1.
    ENDWHILE.
    WHILE last >= first AND cl_abap_conv_out_ce=>uccpi( substring( val = text off = last len = 1 ) ) <= 32.
      last = last - 1.
    ENDWHILE.
    result = substring( val = text off = first len = last - first + 1 ).
  ENDMETHOD.

ENDCLASS.
