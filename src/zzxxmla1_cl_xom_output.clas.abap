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
"! Writes XML as eigenbase-xom's XMLOutput does in its default mode (not compact, no glob, tab indentation, a line
"! break after every tag), so that a definition written by ZZXXMLA1_CL_SCHEMA_DEF reads exactly like the reference's
"! ElementDef.toXML. An attribute without value (null) is left out (XMLAttrVector); attribute values are escaped with
"! xmlNumericEscaper (ampersand, quotes, apostrophe, angle brackets and every character above 127 as a numeric
"! reference), text with stringEncodeXML (the same five characters, tab, line feed and carriage return as numeric
"! references) if it contains one of them.
CLASS zzxxmla1_cl_xom_output DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_attribute,
        name  TYPE string,
        value TYPE string,   " initial: null, the attribute is not written
      END OF ty_attribute,
      ty_t_attribute TYPE STANDARD TABLE OF ty_attribute WITH EMPTY KEY.

    "! beginTag: the start tag with its attributes on a line of its own; what follows is indented one level more.
    METHODS begin_tag
      IMPORTING name       TYPE string
                attributes TYPE ty_t_attribute OPTIONAL.
    "! endTag: the end tag at the indentation of its start tag.
    METHODS end_tag
      IMPORTING name TYPE string.
    "! cdata (not quoted): the text indented, without a line break after it.
    METHODS cdata
      IMPORTING data TYPE string.
    METHODS get_output
      RETURNING VALUE(result) TYPE string.
    "! Boolean.toString of a definition's Boolean: true, false, or initial (null) for abap_undefined.
    CLASS-METHODS boolean_text
      IMPORTING value         TYPE abap_bool
      RETURNING VALUE(result) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA output TYPE string.
    DATA indent TYPE i.

    METHODS display_indent.
    CLASS-METHODS escape_attribute
      IMPORTING value         TYPE string
      RETURNING VALUE(result) TYPE string.
    CLASS-METHODS encode_text
      IMPORTING value         TYPE string
      RETURNING VALUE(result) TYPE string.
    CLASS-METHODS numeric_reference
      IMPORTING char          TYPE string
      RETURNING VALUE(result) TYPE string.
ENDCLASS.



CLASS zzxxmla1_cl_xom_output IMPLEMENTATION.

  METHOD begin_tag.
    display_indent( ).
    output = output && |<{ name }|.
    LOOP AT attributes INTO DATA(attribute) WHERE value IS NOT INITIAL.
      output = output && | { attribute-name }="{ escape_attribute( attribute-value ) }"|.
    ENDLOOP.
    output = output && `>` && cl_abap_char_utilities=>newline.
    indent = indent + 1.
  ENDMETHOD.

  METHOD end_tag.
    indent = indent - 1.
    display_indent( ).
    output = output && |</{ name }>| && cl_abap_char_utilities=>newline.
  ENDMETHOD.

  METHOD cdata.
    display_indent( ).
    output = output && encode_text( data ).
  ENDMETHOD.

  METHOD get_output.
    result = output.
  ENDMETHOD.

  METHOD boolean_text.
    result = SWITCH #( value WHEN abap_true THEN `true` WHEN abap_false THEN `false` ).
  ENDMETHOD.

  METHOD display_indent.
    DO indent TIMES.
      output = output && cl_abap_char_utilities=>horizontal_tab.
    ENDDO.
  ENDMETHOD.

  METHOD escape_attribute.
    DO strlen( value ) TIMES.
      DATA(char) = substring( val = value off = sy-index - 1 len = 1 ).
      IF char CA `&"'<>` OR cl_abap_conv_out_ce=>uccpi( char ) > 127.
        result = result && numeric_reference( char ).
      ELSE.
        result = result && char.
      ENDIF.
    ENDDO.
  ENDMETHOD.

  METHOD encode_text.
    DATA(specials) = `&"'<>` && cl_abap_char_utilities=>horizontal_tab && cl_abap_char_utilities=>newline
                     && cl_abap_char_utilities=>cr_lf(1).
    IF value NA specials.
      result = value.
      RETURN.
    ENDIF.
    DO strlen( value ) TIMES.
      DATA(char) = substring( val = value off = sy-index - 1 len = 1 ).
      result = result && COND string( WHEN char CA specials THEN numeric_reference( char ) ELSE char ).
    ENDDO.
  ENDMETHOD.

  METHOD numeric_reference.
    result = |&#{ cl_abap_conv_out_ce=>uccpi( char ) };|.
  ENDMETHOD.

ENDCLASS.
