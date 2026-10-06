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
    "! @parameter with_schema | true for Content SchemaData (the default), false for Data
    CLASS-METHODS build
      IMPORTING result        TYPE zzxxmla1_cl_mdx_engine=>ty_result
                with_schema   TYPE abap_bool
      RETURNING VALUE(xml)    TYPE string.

  PRIVATE SECTION.
    CONSTANTS c_ns_xmla TYPE string VALUE `urn:schemas-microsoft-com:xml-analysis`.
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
    "! The element name of a property (XmlaUtil.ElementNameEncoder, encodeElementName): every character that the
    "! pattern of a valid first character of an XML name does not match becomes _xHHHH_ (e.g. a space _x0020_).
    CLASS-METHODS element_name
      IMPORTING name          TYPE string
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
    "! The elements of one cell (MDDataSet_Multidimensional.emitCell); empty if the cell is left out.
    CLASS-METHODS cell_xml
      IMPORTING cell          TYPE zzxxmla1_cl_mdx_engine=>ty_cell
                properties    TYPE string_table
      RETURNING VALUE(result) TYPE string.
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

    DATA(cells) = VALUE string( ).
    LOOP AT result-cells INTO DATA(cell).
      cells = cells && cell_xml( cell = cell properties = result-cell_properties ).
    ENDLOOP.
    DATA(cell_info) = VALUE string( ).
    LOOP AT result-cell_properties INTO DATA(cell_property_name).
      cell_property( EXPORTING name = cell_property_name IMPORTING element = DATA(element) type = DATA(type) ).
      IF element IS NOT INITIAL.
        cell_info = cell_info && |          <{ element } name="{ cell_property_name }"| &&
          COND string( WHEN type IS NOT INITIAL THEN | type="{ type }"| ) && `/>` && nl.
      ENDIF.
    ENDLOOP.

    xml =
      `<?xml version="1.0" encoding="UTF-8"?>` && nl &&
      `<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">` && nl &&
      `<SOAP-ENV:Header>` && nl &&
      `</SOAP-ENV:Header>` && nl &&
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
      COND string( WHEN cells IS INITIAL THEN `      <CellData/>` && nl
                   ELSE `      <CellData>` && nl && cells && `      </CellData>` && nl ) &&
      `    </root>` && nl &&
      `  </return>` && nl &&
      `</ExecuteResponse>` && nl &&
      `</SOAP-ENV:Body>` && nl &&
      `</SOAP-ENV:Envelope>` && nl.
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

  METHOD cell_xml.
    " the values of the asked properties that the cell has: no Value for an empty cell, an empty FmtValue, the format
    " string, font flags 0; LANGUAGE, BACK_COLOR and FORE_COLOR have none. A cell with none of them is left out, except
    " the first. An unknown cell property is left out (the reference's writer fails on one).
    DATA(nl) = cl_abap_char_utilities=>newline.
    DATA(elements) = VALUE string( ).
    DATA(any) = abap_false.
    LOOP AT properties INTO DATA(property).
      CASE property.
        WHEN `VALUE`.
          IF cell-empty = abap_false.
            elements = elements && |          <Value xsi:type="{ cell-value_type }">{ text( cell-value ) }</Value>| && nl.
            any = abap_true.
          ENDIF.
        WHEN `FORMATTED_VALUE`.
          elements = elements && COND string( WHEN cell-empty = abap_true THEN `          <FmtValue/>`
                                              ELSE |          <FmtValue>{ text( cell-formatted ) }</FmtValue>| ) && nl.
          any = abap_true.
        WHEN `FORMAT_STRING`.
          elements = elements && COND string( WHEN cell-format_string IS INITIAL THEN `          <FormatString/>`
                                              ELSE |          <FormatString>{ text( cell-format_string ) }</FormatString>| ) && nl.
          any = abap_true.
        WHEN `FONT_FLAGS`.
          elements = elements && `          <FontFlags>0</FontFlags>` && nl.
          any = abap_true.
      ENDCASE.
    ENDLOOP.
    IF any = abap_false AND cell-ordinal <> 0.
      RETURN.
    ENDIF.
    IF elements IS INITIAL.
      result = |        <Cell CellOrdinal="{ cell-ordinal }"/>| && nl.
    ELSE.
      result = |        <Cell CellOrdinal="{ cell-ordinal }">| && nl && elements && `        </Cell>` && nl.
    ENDIF.
  ENDMETHOD.

  METHOD axis_xml.
    DATA(nl) = cl_abap_char_utilities=>newline.
    result = |        <Axis name="{ name }">| && nl.
    IF tuples IS INITIAL.
      result = result && `          <Tuples/>` && nl.
    ELSE.
      result = result && `          <Tuples>` && nl.
      LOOP AT tuples INTO DATA(tuple).
        result = result && tuple_xml( tuple = tuple properties = properties values = values
                                      level_properties = level_properties ).
      ENDLOOP.
      result = result && `          </Tuples>` && nl.
    ENDIF.
    result = result && `        </Axis>` && nl.
  ENDMETHOD.

ENDCLASS.
