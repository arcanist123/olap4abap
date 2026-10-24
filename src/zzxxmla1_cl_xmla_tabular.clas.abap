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
"! The answer of an Execute request in the tabular format, the rows of a drill-through (XmlaHandler.TabularRowSet): a
"! rowset whose XML schema has an element per column, named by the column (encoded as an XML name) with the column's
"! name as sql:field and its XML schema type, and a row element per row with an element per column.
CLASS zzxxmla1_cl_xmla_tabular DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! @parameter with_schema | the rowset's XML schema (Content Schema and SchemaData, the default)
    "! @parameter with_data | the rows (Content Data and SchemaData)
    CLASS-METHODS build
      IMPORTING rowset        TYPE zzxxmla1_cl_mdx_facts=>ty_drill_through
                with_schema   TYPE abap_bool
                with_data     TYPE abap_bool
      RETURNING VALUE(xml)    TYPE string.

  PRIVATE SECTION.
    CONSTANTS c_ns_xmla TYPE string VALUE `urn:schemas-microsoft-com:xml-analysis`.
    "! TabularRowSet.metadata: the rowset's XML schema.
    CLASS-METHODS metadata
      IMPORTING columns       TYPE zzxxmla1_cl_mdx_facts=>ty_t_drill_column
      RETURNING VALUE(result) TYPE string.
ENDCLASS.

CLASS zzxxmla1_cl_xmla_tabular IMPLEMENTATION.

  METHOD build.
    DATA(nl) = cl_abap_char_utilities=>newline.
    DATA(names) = VALUE string_table( FOR c IN rowset-columns ( zzxxmla1_cl_xmla_mddataset=>element_name( c-name ) ) ).

    " TabularRowSet.unparse: per row an element per column with its type; the pieces are joined once
    DATA(lines) = VALUE string_table( ).
    IF with_data = abap_true.
      LOOP AT rowset-rows INTO DATA(row).
        DATA(nulls) = VALUE string( rowset-nulls[ sy-tabix ] OPTIONAL ).
        APPEND `      <row>` && nl TO lines.
        LOOP AT row INTO DATA(value).
          DATA(column) = sy-tabix.
          " a NULL value has no element
          IF column <= strlen( nulls ) AND substring( val = nulls off = column - 1 len = 1 ) = `1`.
            CONTINUE.
          ENDIF.
          APPEND |        <{ names[ column ] } xsi:type="{ rowset-columns[ column ]-xsd_type }">| &&
                 |{ escape( val = value format = cl_abap_format=>e_xml_text ) }</{ names[ column ] }>{ nl }| TO lines.
        ENDLOOP.
        APPEND `      </row>` && nl TO lines.
      ENDLOOP.
    ENDIF.

    xml =
      `<?xml version="1.0" encoding="UTF-8"?>` && nl &&
      `<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">` && nl &&
      `<SOAP-ENV:Header>` && nl &&
      `</SOAP-ENV:Header>` && nl &&
      `<SOAP-ENV:Body>` && nl &&
      `<ExecuteResponse xmlns="` && c_ns_xmla && `">` && nl &&
      `  <return>` && nl &&
      `    <root xmlns="` && c_ns_xmla && `:rowset" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:EX="` && c_ns_xmla && `:exception">` && nl &&
      COND string( WHEN with_schema = abap_true THEN metadata( rowset-columns ) ) &&
      concat_lines_of( lines ) &&
      `    </root>` && nl &&
      `  </return>` && nl &&
      `</ExecuteResponse>` && nl &&
      `</SOAP-ENV:Body>` && nl &&
      `</SOAP-ENV:Envelope>` && nl.
  ENDMETHOD.

  METHOD metadata.
    DATA(nl) = cl_abap_char_utilities=>newline.
    DATA(elements) = VALUE string_table( ).
    LOOP AT columns INTO DATA(column).
      APPEND |            <xsd:element minOccurs="0" name="{ zzxxmla1_cl_xmla_mddataset=>element_name( column-name ) }"| &&
             | sql:field="{ escape( val = column-name format = cl_abap_format=>e_xml_attr ) }"| &&
             | type="{ column-xsd_type }"/>{ nl }| TO elements.
    ENDLOOP.
    result =
      `      <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema" targetNamespace="` && c_ns_xmla && `:rowset"` &&
      ` xmlns="` && c_ns_xmla && `:rowset" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"` &&
      ` xmlns:sql="urn:schemas-microsoft-com:xml-sql" elementFormDefault="qualified">` && nl &&
      `        <xsd:element name="root">` && nl &&
      `          <xsd:complexType>` && nl &&
      `            <xsd:sequence>` && nl &&
      `              <xsd:element maxOccurs="unbounded" minOccurs="0" name="row" type="row"/>` && nl &&
      `            </xsd:sequence>` && nl &&
      `          </xsd:complexType>` && nl &&
      `        </xsd:element>` && nl &&
      `        <xsd:simpleType name="uuid">` && nl &&
      `          <xsd:restriction base="xsd:string">` && nl &&
      `            <xsd:pattern value="[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"/>` && nl &&
      `          </xsd:restriction>` && nl &&
      `        </xsd:simpleType>` && nl &&
      `        <xsd:complexType name="row">` && nl &&
      `          <xsd:sequence>` && nl &&
      concat_lines_of( elements ) &&
      `          </xsd:sequence>` && nl &&
      `        </xsd:complexType>` && nl &&
      `      </xsd:schema>` && nl.
  ENDMETHOD.

ENDCLASS.
