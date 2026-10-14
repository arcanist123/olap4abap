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
"! The answer of an Execute request in the multidimensional format (Format Multidimensional, AxisFormat TupleFormat):
"! the SOAP envelope with the schema (Content SchemaData), OlapInfo, the axes and the cells, as the reference writes it.
CLASS zzxxmla1_cl_xmla_mddataset DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! The answer in UTF-8, in parts the endpoint appends to the response one after the other.
    TYPES ty_t_part TYPE STANDARD TABLE OF xstring WITH EMPTY KEY.

    "! The answer in UTF-8 parts: the head with the axes, the cells by c_cells_per_part, the tail. A grid's answer has
    "! some hundred megabytes; joined into one string it would be copied and converted to UTF-8 as a whole.
    "! @parameter session | the Session element of the SOAP header (ZZXXMLA1_CL_XMLA_HANDLER), empty for none
    "! @parameter with_schema | true for Content SchemaData (the default), false for Data
    "! @parameter excel | true if the client is Excel: an Integer cell is xsd:int, as the reference's release writes it
    "!   (Excel drops the filter of Keep Only Selected Items after an xsd:integer child count of its item path query);
    "!   for other clients xsd:integer, as the reference writes it since it was changed for Power BI
    CLASS-METHODS build
      IMPORTING result        TYPE zzxxmla1_cl_mdx_engine=>ty_result
                with_schema   TYPE abap_bool
                excel         TYPE abap_bool DEFAULT abap_false
                session       TYPE string OPTIONAL
      RETURNING VALUE(parts)  TYPE ty_t_part.
    "! The element name of a property or a column (XmlaUtil.ElementNameEncoder, encodeElementName): every character
    "! that the pattern of a valid first character of an XML name does not match becomes _xHHHH_ (a space _x0020_).
    CLASS-METHODS element_name
      IMPORTING name          TYPE string
      RETURNING VALUE(result) TYPE string.

  PRIVATE SECTION.
    CONSTANTS c_ns_xmla TYPE string VALUE `urn:schemas-microsoft-com:xml-analysis`.
    "! the cells converted to UTF-8 together (docs/query-planning.md, Cells first: 10,000 measured fastest)
    CONSTANTS c_cells_per_part TYPE i VALUE 10000.
    CLASS-METHODS utf8
      IMPORTING value         TYPE string
      RETURNING VALUE(result) TYPE xstring.
    CLASS-METHODS text
      IMPORTING value         TYPE string
      RETURNING VALUE(result) TYPE string.
    "! The HierarchyInfo elements of an axis: one per hierarchy of its first tuple, in tuple order; of an empty axis
    "! one per hierarchy of its set type (the axis metadata).
    "! A property of a level is listed in the HierarchyInfo of its hierarchy only, without a type (writeProperty).
    CLASS-METHODS hierarchy_infos
      IMPORTING tuples           TYPE zzxxmla1_cl_mdx_engine=>ty_t_tuple
                hierarchies      TYPE string_table OPTIONAL
                properties       TYPE string_table OPTIONAL
                level_properties TYPE zzxxmla1_cl_mdx_engine=>ty_t_level_property OPTIONAL
      RETURNING VALUE(result) TYPE string.
    "! The XML schema type of a standard member property (its olap4j datatype).
    CLASS-METHODS property_type
      IMPORTING name          TYPE string
      RETURNING VALUE(result) TYPE string.
    "! The element and XML schema type of a cell property (MDDataSet.cellPropertyMap); empty element: not known.
    CLASS-METHODS cell_property
      IMPORTING name    TYPE string
      EXPORTING element TYPE string
                type    TYPE string.
    TYPES ty_t_code TYPE STANDARD TABLE OF i WITH EMPTY KEY.
    "! The cell properties as cell_xml writes them, in their order: 1 VALUE, 2 FORMATTED_VALUE, 3 FORMAT_STRING,
    "! 4 FONT_FLAGS; the others have no element in a cell.
    CLASS-METHODS cell_codes
      IMPORTING properties    TYPE string_table
      RETURNING VALUE(result) TYPE ty_t_code.
    "! The elements of one cell (MDDataSet_Multidimensional.emitCell); empty if the cell is left out.
    "! @parameter codes | the cell properties asked for (cell_codes)
    CLASS-METHODS cell_xml
      IMPORTING cell          TYPE zzxxmla1_cl_mdx_engine=>ty_cell
                codes         TYPE ty_t_code
                excel         TYPE abap_bool
      RETURNING VALUE(result) TYPE string.
    "! The elements inside a cell's Cell element; any: it has one (a cell without is left out, but the first).
    CLASS-METHODS cell_elements
      IMPORTING cell     TYPE zzxxmla1_cl_mdx_engine=>ty_cell
                codes    TYPE ty_t_code
                excel    TYPE abap_bool
      EXPORTING elements TYPE string
                any      TYPE abap_bool.
    CLASS-METHODS axis_info
      IMPORTING name             TYPE string
                tuples           TYPE zzxxmla1_cl_mdx_engine=>ty_t_tuple
                hierarchies      TYPE string_table OPTIONAL
                properties       TYPE string_table OPTIONAL
                level_properties TYPE zzxxmla1_cl_mdx_engine=>ty_t_level_property OPTIONAL
      RETURNING VALUE(result) TYPE string.
    "! The value of a property of a level carries the XML schema type of the property (writeMember).
    CLASS-METHODS tuple_xml
      IMPORTING tuple            TYPE zzxxmla1_cl_mdx_engine=>ty_tuple
                properties       TYPE string_table OPTIONAL
                values           TYPE zzxxmla1_cl_mdx_engine=>ty_t_property_value OPTIONAL
                level_properties TYPE zzxxmla1_cl_mdx_engine=>ty_t_level_property OPTIONAL
      RETURNING VALUE(result) TYPE string.
    CLASS-METHODS axis_xml
      IMPORTING name             TYPE string
                tuples           TYPE zzxxmla1_cl_mdx_engine=>ty_t_tuple
                properties       TYPE string_table OPTIONAL
                values           TYPE zzxxmla1_cl_mdx_engine=>ty_t_property_value OPTIONAL
                level_properties TYPE zzxxmla1_cl_mdx_engine=>ty_t_level_property OPTIONAL
      RETURNING VALUE(result) TYPE string.
ENDCLASS.

CLASS zzxxmla1_cl_xmla_mddataset IMPLEMENTATION.

  METHOD build.
    DATA(nl) = cl_abap_char_utilities=>newline.
    DATA(timestamp) = |{ result-last_update TIMESTAMP = ISO }|.

    DATA(axes_info) = VALUE string( ).
    DATA(axes_data) = VALUE string( ).
    LOOP AT result-axes INTO DATA(axis).
      axes_info = axes_info && axis_info( name = axis-name tuples = axis-tuples hierarchies = axis-hierarchies
                                          properties = axis-properties level_properties = axis-level_properties ).
      axes_data = axes_data && axis_xml( name = axis-name tuples = axis-tuples properties = axis-properties
                                         values = axis-values level_properties = axis-level_properties ).
    ENDLOOP.
    IF result-has_slicer = abap_true.
      axes_info = axes_info && axis_info( name = `SlicerAxis` tuples = result-slicer ).
      axes_data = axes_data && axis_xml( name = `SlicerAxis` tuples = result-slicer ).
    ELSE.
      axes_info = axes_info && `          <AxisInfo name="SlicerAxis"/>` && nl.
    ENDIF.

    " the cells' lines are joined and converted to UTF-8 by c_cells_per_part: appending to a string copies the string
    " every time, and a grid's answer has some hundred megabytes
    DATA(cell_lines) = VALUE string_table( ).
    DATA(cell_parts) = VALUE ty_t_part( ).
    DATA(has_cells) = abap_false.
    DATA(codes) = cell_codes( result-cell_properties ).
    LOOP AT result-cells ASSIGNING FIELD-SYMBOL(<cell>).
      " the cube's annotation olap4abap.omitEmptyCells (our extension): only the cells with a value, and the first
      IF result-omit_empty_cells = abap_true AND <cell>-empty = abap_true AND <cell>-ordinal <> 0.
        CONTINUE.
      ENDIF.
      has_cells = abap_true.
      APPEND cell_xml( cell = <cell> codes = codes excel = excel ) TO cell_lines.
      IF lines( cell_lines ) = c_cells_per_part.
        APPEND utf8( concat_lines_of( cell_lines ) ) TO cell_parts.
        CLEAR cell_lines.
      ENDIF.
    ENDLOOP.
    " cells first (cell_values and cell_refs): the elements of each distinct cell written once, and whether a cell
    " with it is left out
    DATA(bodies) = VALUE string_table( ).
    DATA skipped TYPE STANDARD TABLE OF abap_bool WITH EMPTY KEY.
    LOOP AT result-cell_values ASSIGNING <cell>.
      cell_elements( EXPORTING cell = <cell> codes = codes excel = excel
                     IMPORTING elements = DATA(elements) any = DATA(any) ).
      APPEND elements TO bodies.
      APPEND xsdbool( any = abap_false OR ( result-omit_empty_cells = abap_true AND <cell>-empty = abap_true ) )
             TO skipped.
    ENDLOOP.
    LOOP AT result-cell_refs INTO DATA(ref).
      DATA(ordinal) = sy-tabix - 1.
      IF ordinal <> 0 AND skipped[ ref ] = abap_true.
        CONTINUE.
      ENDIF.
      has_cells = abap_true.
      ASSIGN bodies[ ref ] TO FIELD-SYMBOL(<body>).
      IF <body> IS INITIAL.
        APPEND |        <Cell CellOrdinal="{ ordinal }"/>\n| TO cell_lines.
      ELSE.
        APPEND |        <Cell CellOrdinal="{ ordinal }">\n{ <body> }        </Cell>\n| TO cell_lines.
      ENDIF.
      IF lines( cell_lines ) = c_cells_per_part.
        APPEND utf8( concat_lines_of( cell_lines ) ) TO cell_parts.
        CLEAR cell_lines.
      ENDIF.
    ENDLOOP.
    IF cell_lines IS NOT INITIAL.
      APPEND utf8( concat_lines_of( cell_lines ) ) TO cell_parts.
      CLEAR cell_lines.
    ENDIF.
    DATA(cell_info) = VALUE string( ).
    LOOP AT result-cell_properties INTO DATA(cell_property_name).
      cell_property( EXPORTING name = cell_property_name IMPORTING element = DATA(element) type = DATA(type) ).
      IF element IS NOT INITIAL.
        cell_info = cell_info && |          <{ element } name="{ cell_property_name }"| &&
          COND string( WHEN type IS NOT INITIAL THEN | type="{ type }"| ) && `/>` && nl.
      ENDIF.
    ENDLOOP.

    DATA(head) =
      `<?xml version="1.0" encoding="UTF-8"?>` && nl &&
      `<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">` && nl &&
      `<SOAP-ENV:Header>` && nl &&
      session && `</SOAP-ENV:Header>` && nl &&
      `<SOAP-ENV:Body>` && nl &&
      `<ExecuteResponse xmlns="` && c_ns_xmla && `">` && nl &&
      `  <return>` && nl &&
      `    <root xmlns="` && c_ns_xmla && `:mddataset" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:EX="` && c_ns_xmla && `:exception">` && nl &&
      COND string( WHEN with_schema = abap_true THEN zzxxmla1_cl_xmla_mdschema=>get( ) ) &&
      `      <OlapInfo>` && nl &&
      `        <CubeInfo>` && nl &&
      `          <Cube>` && nl &&
      `            <CubeName>` && text( result-cube_name ) && `</CubeName>` && nl &&
      `            <LastDataUpdate xmlns="http://schemas.microsoft.com/analysisservices/2003/engine">` && timestamp && `</LastDataUpdate>` && nl &&
      `            <LastSchemaUpdate xmlns="http://schemas.microsoft.com/analysisservices/2003/engine">` && timestamp && `</LastSchemaUpdate>` && nl &&
      `          </Cube>` && nl &&
      `        </CubeInfo>` && nl &&
      `        <AxesInfo>` && nl &&
      axes_info &&
      `        </AxesInfo>` && nl &&
      `        <CellInfo>` && nl &&
      cell_info &&
      `        </CellInfo>` && nl &&
      `      </OlapInfo>` && nl &&
      COND string( WHEN axes_data IS INITIAL THEN `      <Axes/>` && nl
                   ELSE `      <Axes>` && nl && axes_data && `      </Axes>` && nl ) &&
      COND string( WHEN has_cells = abap_false THEN `      <CellData/>` && nl
                   ELSE `      <CellData>` && nl ).
    DATA(tail) =
      COND string( WHEN has_cells = abap_true THEN `      </CellData>` && nl ) &&
      `    </root>` && nl &&
      `  </return>` && nl &&
      `</ExecuteResponse>` && nl &&
      `</SOAP-ENV:Body>` && nl &&
      `</SOAP-ENV:Envelope>` && nl.
    APPEND utf8( head ) TO parts.
    APPEND LINES OF cell_parts TO parts.
    APPEND utf8( tail ) TO parts.
  ENDMETHOD.

  METHOD utf8.
    result = cl_abap_codepage=>convert_to( value ).
  ENDMETHOD.

  METHOD text.
    result = escape( val = value format = cl_abap_format=>e_xml_text ).
  ENDMETHOD.

  METHOD hierarchy_infos.
    DATA(nl) = cl_abap_char_utilities=>newline.
    DATA(names) = COND string_table( WHEN tuples IS INITIAL THEN hierarchies
                                     ELSE VALUE #( FOR m IN tuples[ 1 ] ( m-hierarchy ) ) ).
    LOOP AT names INTO DATA(name).
      DATA(h) = text( name ).
      result = result &&
        |            <HierarchyInfo name="{ h }">| && nl &&
        |              <UName name="{ h }.[MEMBER_UNIQUE_NAME]" type="xsd:string"/>| && nl &&
        |              <Caption name="{ h }.[MEMBER_CAPTION]" type="xsd:string"/>| && nl &&
        |              <LName name="{ h }.[LEVEL_UNIQUE_NAME]" type="xsd:string"/>| && nl &&
        |              <LNum name="{ h }.[LEVEL_NUMBER]" type="xsd:unsignedInt"/>| && nl &&
        |              <DisplayInfo name="{ h }.[DISPLAY_INFO]" type="xsd:unsignedInt"/>| && nl.
      LOOP AT properties INTO DATA(property).
        READ TABLE level_properties INTO DATA(level_property) WITH KEY name = property.
        IF sy-subrc = 0.
          IF level_property-hierarchy = name.
            result = result && |              <{ element_name( property ) } | &&
                               |name="{ h }.{ text( zzxxmla1_cl_mdx_node=>quote_identifier( property ) ) }"/>| && nl.
          ENDIF.
          CONTINUE.
        ENDIF.
        result = result && |              <{ element_name( property ) } name="{ h }.[{ text( property ) }]"| &&
                           | type="{ property_type( property ) }"/>| && nl.
      ENDLOOP.
      result = result && `            </HierarchyInfo>` && nl.
    ENDLOOP.
  ENDMETHOD.

  METHOD axis_info.
    DATA(nl) = cl_abap_char_utilities=>newline.
    DATA(infos) = hierarchy_infos( tuples = tuples hierarchies = hierarchies properties = properties
                                   level_properties = level_properties ).
    IF infos IS INITIAL.
      result = |          <AxisInfo name="{ name }"/>| && nl.
    ELSE.
      result = |          <AxisInfo name="{ name }">| && nl && infos && `          </AxisInfo>` && nl.
    ENDIF.
  ENDMETHOD.

  METHOD tuple_xml.
    DATA(nl) = cl_abap_char_utilities=>newline.
    result = `            <Tuple>` && nl.
    LOOP AT tuple INTO DATA(member).
      result = result &&
        |              <Member Hierarchy="{ text( member-hierarchy ) }">| && nl &&
        |                <UName>{ text( member-unique_name ) }</UName>| && nl &&
        |                <Caption>{ text( member-caption ) }</Caption>| && nl &&
        |                <LName>{ text( member-level_name ) }</LName>| && nl &&
        |                <LNum>{ member-level_number }</LNum>| && nl &&
        |                <DisplayInfo>{ member-display_info }</DisplayInfo>| && nl.
      " the dimension properties with a value; DISPLAY_INFO is the one of the member in this tuple
      LOOP AT properties INTO DATA(property).
        IF property = `DISPLAY_INFO`.
          DATA(value) = CONV string( member-display_info ).
        ELSE.
          READ TABLE values INTO DATA(entry) WITH TABLE KEY member = member-unique_name name = property.
          IF sy-subrc <> 0.
            CONTINUE.
          ENDIF.
          value = entry-value.
        ENDIF.
        DATA(element) = element_name( property ).
        READ TABLE level_properties INTO DATA(level_property) WITH KEY name = property.
        DATA(type) = COND string( WHEN sy-subrc = 0 THEN | xsi:type="{ level_property-xsd_type }"| ).
        result = result && |                <{ element }{ type }>{ text( value ) }</{ element }>| && nl.
      ENDLOOP.
      result = result && `              </Member>` && nl.
    ENDLOOP.
    result = result && `            </Tuple>` && nl.
  ENDMETHOD.

  METHOD element_name.
    DO strlen( name ) TIMES.
      DATA(char) = substring( val = name off = sy-index - 1 len = 1 ).
      DATA(code) = cl_abap_conv_out_ce=>uccpi( char ).
      " [:A-Z_a-zÀÖØ-öø-˿Ͱ-ͽͿ-῿‌‍⁰-↏
      " Ⰰ-⿯、-퟿豈-﷏ﷰ-�]
      IF char = `:` OR char = `_` OR ( code >= 65 AND code <= 90 ) OR ( code >= 97 AND code <= 122 )
          OR code = 192 OR code = 214 OR ( code >= 216 AND code <= 246 ) OR ( code >= 248 AND code <= 767 )
          OR ( code >= 880 AND code <= 893 ) OR ( code >= 895 AND code <= 8191 ) OR code = 8204 OR code = 8205
          OR ( code >= 8304 AND code <= 8591 ) OR ( code >= 11264 AND code <= 12271 )
          OR ( code >= 12289 AND code <= 55295 ) OR ( code >= 63744 AND code <= 64975 )
          OR ( code >= 65008 AND code <= 65533 ).
        result = result && char.
      ELSE.
        DATA hex TYPE x LENGTH 2.
        hex = code.
        result = |{ result }_x{ to_lower( CONV string( hex ) ) }_|.
      ENDIF.
    ENDDO.
  ENDMETHOD.

  METHOD property_type.
    CASE name.
      WHEN `LEVEL_NUMBER` OR `MEMBER_ORDINAL` OR `CHILDREN_CARDINALITY` OR `PARENT_LEVEL` OR `PARENT_COUNT` OR `DEPTH`
        OR `DISPLAY_INFO`.
        result = `xsd:unsignedInt`.
      WHEN `$visible` OR `IS_PLACEHOLDERMEMBER` OR `IS_DATAMEMBER`.
        result = `xsd:boolean`.
      WHEN OTHERS.
        result = `xsd:string`.
    ENDCASE.
  ENDMETHOD.

  METHOD cell_property.
    CLEAR: element, type.
    CASE name.
      WHEN `CELL_ORDINAL`.
        element = `CellOrdinal`.
        type = `xsd:unsignedInt`.
      WHEN `VALUE`.
        element = `Value`.
      WHEN `FORMATTED_VALUE`.
        element = `FmtValue`.
        type = `xsd:string`.
      WHEN `FORMAT_STRING`.
        element = `FormatString`.
        type = `xsd:string`.
      WHEN `LANGUAGE`.
        element = `Language`.
        type = `xsd:unsignedInt`.
      WHEN `BACK_COLOR`.
        element = `BackColor`.
        type = `xsd:unsignedInt`.
      WHEN `FORE_COLOR`.
        element = `ForeColor`.
        type = `xsd:unsignedInt`.
      WHEN `FONT_FLAGS`.
        element = `FontFlags`.
        type = `xsd:int`.
    ENDCASE.
  ENDMETHOD.

  METHOD cell_codes.
    LOOP AT properties INTO DATA(property).
      CASE property.
        WHEN `VALUE`.
          APPEND 1 TO result.
        WHEN `FORMATTED_VALUE`.
          APPEND 2 TO result.
        WHEN `FORMAT_STRING`.
          APPEND 3 TO result.
        WHEN `FONT_FLAGS`.
          APPEND 4 TO result.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

  METHOD cell_xml.
    cell_elements( EXPORTING cell = cell codes = codes excel = excel IMPORTING elements = DATA(elements) any = DATA(any) ).
    IF any = abap_false AND cell-ordinal <> 0.
      RETURN.
    ENDIF.
    IF elements IS INITIAL.
      result = |        <Cell CellOrdinal="{ cell-ordinal }"/>\n|.
    ELSE.
      result = |        <Cell CellOrdinal="{ cell-ordinal }">\n{ elements }        </Cell>\n|.
    ENDIF.
  ENDMETHOD.

  METHOD cell_elements.
    " the values of the asked properties that the cell has: no Value for an empty cell, an empty FmtValue, the format
    " string, font flags 0; LANGUAGE, BACK_COLOR and FORE_COLOR have none. A cell with none of them is left out, except
    " the first. An unknown cell property is left out (the reference's writer fails on one).
    " one string template per element: a grid writes some hundred thousand cells, and each piece appended is a copy
    CLEAR: elements, any.
    LOOP AT codes INTO DATA(code).
      CASE code.
        WHEN 1.
          IF cell-empty = abap_false.
            DATA(value_type) = COND string( WHEN excel = abap_true AND cell-value_type = `xsd:integer` THEN `xsd:int`
                                            ELSE cell-value_type ).
            " a number's text has nothing to escape
            IF value_type = `xsd:double`.
              elements = |{ elements }          <Value xsi:type="xsd:double">{ cell-value }</Value>\n|.
            ELSE.
              elements = |{ elements }          <Value xsi:type="{ value_type }">{ text( cell-value ) }</Value>\n|.
            ENDIF.
            any = abap_true.
          ENDIF.
        WHEN 2.
          IF cell-empty = abap_true.
            elements = |{ elements }          <FmtValue/>\n|.
          ELSE.
            elements = |{ elements }          <FmtValue>{ text( cell-formatted ) }</FmtValue>\n|.
          ENDIF.
          any = abap_true.
        WHEN 3.
          IF cell-format_string IS INITIAL.
            elements = |{ elements }          <FormatString/>\n|.
          ELSE.
            elements = |{ elements }          <FormatString>{ text( cell-format_string ) }</FormatString>\n|.
          ENDIF.
          any = abap_true.
        WHEN 4.
          elements = |{ elements }          <FontFlags>0</FontFlags>\n|.
          any = abap_true.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

  METHOD axis_xml.
    DATA(nl) = cl_abap_char_utilities=>newline.
    result = |        <Axis name="{ name }">| && nl.
    IF tuples IS INITIAL.
      result = result && `          <Tuples/>` && nl.
    ELSE.
      " the pieces are joined once: appending a method's result to a string copies the string every time
      DATA(tuple_lines) = VALUE string_table( ).
      LOOP AT tuples INTO DATA(tuple).
        APPEND tuple_xml( tuple = tuple properties = properties values = values
                          level_properties = level_properties ) TO tuple_lines.
      ENDLOOP.
      result = result && `          <Tuples>` && nl && concat_lines_of( tuple_lines ) && `          </Tuples>` && nl.
    ENDIF.
    result = result && `        </Axis>` && nl.
  ENDMETHOD.

ENDCLASS.
