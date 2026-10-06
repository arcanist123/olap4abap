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
"! The files of the XMLA server, what the files of its web application are to the reference: the data sources file
"! /WEB-INF/datasources.xml (ZZXXMLA1_CL_REPOSITORY) and the schema files its catalogs name in Definition
"! (/WEB-INF/schema/FoodmartBW.xml, ...). They are rows of table ZZXXMLA1_FILE under their path, so a schema or a
"! catalog is added without any new ABAP object. The server writes them only in the schema generator's accept
"! (ZZXXMLA1_CL_SCHEMA_API); scripts/sap-files.py writes them as the developer who logs on (sapcli abap run).
CLASS zzxxmla1_cl_files DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_file,
        path       TYPE string,
        content    TYPE string,
        changed_at TYPE timestampl,  " UTC
        changed_by TYPE syuname,
      END OF ty_file,
      ty_t_file TYPE STANDARD TABLE OF ty_file WITH EMPTY KEY.

    "! The reference's default data sources file (XmlaServlet's DataSourcesConfig).
    CONSTANTS c_datasources TYPE string VALUE `/WEB-INF/datasources.xml`.

    "! The file of the path; its path is initial if there is none.
    CLASS-METHODS read
      IMPORTING !path         TYPE csequence
      RETURNING VALUE(result) TYPE ty_file.
    "! The files sorted by path, without their content.
    CLASS-METHODS list
      RETURNING VALUE(result) TYPE ty_t_file.
    "! Writes the file (a new one or a new content), changed now by the user; the caller commits.
    CLASS-METHODS write
      IMPORTING !path    TYPE csequence
                !content TYPE string.
    "! Deletes the file; the caller commits.
    CLASS-METHODS delete
      IMPORTING !path TYPE csequence.
    "! The data sources file of a new server: one data source without catalogs (ZZXXMLA1_CL_SETUP writes it).
    CLASS-METHODS default_datasources
      RETURNING VALUE(result) TYPE string.
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zzxxmla1_cl_files IMPLEMENTATION.

  METHOD read.
    DATA key TYPE zzxxmla1_file-path.
    key = path.
    SELECT SINGLE path, content, changed_at, changed_by FROM zzxxmla1_file
      WHERE path = @key
      INTO CORRESPONDING FIELDS OF @result.
  ENDMETHOD.

  METHOD list.
    SELECT path, changed_at, changed_by FROM zzxxmla1_file
      ORDER BY path ASCENDING
      INTO CORRESPONDING FIELDS OF TABLE @result.
  ENDMETHOD.

  METHOD write.
    DATA row TYPE zzxxmla1_file.
    row-path = path.
    row-content = content.
    row-changed_by = sy-uname.
    GET TIME STAMP FIELD row-changed_at.
    MODIFY zzxxmla1_file FROM @row.
  ENDMETHOD.

  METHOD delete.
    DATA key TYPE zzxxmla1_file-path.
    key = path.
    DELETE FROM zzxxmla1_file WHERE path = @key.
  ENDMETHOD.

  METHOD default_datasources.
    " as reference/schema/datasources-sap.xml, without its catalog: an empty URL makes DISCOVER_DATASOURCES give the
    " URL the request came in on; a catalog is added by the schema builder's accept or by a generator
    result = |<?xml version="1.0"?>\n| &&
             |<DataSources>\n| &&
             |  <DataSource>\n| &&
             |    <DataSourceName>ABAP BW</DataSourceName>\n| &&
             |    <DataSourceDescription>SAP BW data served by olap4abap</DataSourceDescription>\n| &&
             |    <URL></URL>\n| &&
             |    <DataSourceInfo>Provider=olap4abap</DataSourceInfo>\n| &&
             |    <ProviderName>olap4abap</ProviderName>\n| &&
             |    <ProviderType>MDP</ProviderType>\n| &&
             |    <AuthenticationMode>Unauthenticated</AuthenticationMode>\n| &&
             |    <Catalogs>\n| &&
             |    </Catalogs>\n| &&
             |  </DataSource>\n| &&
             |</DataSources>\n|.
  ENDMETHOD.

ENDCLASS.
