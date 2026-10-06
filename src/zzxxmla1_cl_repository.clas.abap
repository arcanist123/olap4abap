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
"! The data sources and catalogs of the server: FileRepository over its data sources file, read as
"! DataSourcesConfig reads it (eigenbase-xom, ZZXXMLA1_CL_XOM_PARSER) from the server's file /WEB-INF/datasources.xml
"! (ZZXXMLA1_CL_FILES). A data source is what XMLA calls a database (DISCOVER_DATASOURCES, the DataSourceInfo
"! property); each of its catalogs names the file of its schema in Definition, a path of the server's files
"! (ZZXXMLA1_CL_SCHEMA reads them). The connect strings are kept as written: Jdbc and the like are for the reference server, which
"! can read the same file, while this server reads every catalog's tables from its own database.
CLASS zzxxmla1_cl_repository DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    TYPES:
      "! DataSourcesConfig.Catalog
      BEGIN OF ty_catalog,
        name             TYPE string,  " attribute name, required
        data_source_info TYPE string,  " element DataSourceInfo, optional: the data source's, else
        definition       TYPE string,  " element Definition, required: the path of the schema file
      END OF ty_catalog,
      ty_t_catalog TYPE STANDARD TABLE OF ty_catalog WITH EMPTY KEY.
    TYPES:
      "! DataSourcesConfig.DataSource; every element is required
      BEGIN OF ty_data_source,
        name                TYPE string,  " DataSourceName
        description         TYPE string,  " DataSourceDescription
        url                 TYPE string,  " URL
        data_source_info    TYPE string,  " DataSourceInfo: the connect string
        provider_name       TYPE string,  " ProviderName
        provider_type       TYPE string,  " ProviderType (DISCOVER_DATASOURCES shows MDP)
        authentication_mode TYPE string,  " AuthenticationMode
        catalogs            TYPE ty_t_catalog,
      END OF ty_data_source,
      ty_t_data_source TYPE STANDARD TABLE OF ty_data_source WITH EMPTY KEY.
    TYPES:
      "! a pair of Util.PropertyList
      BEGIN OF ty_property,
        name  TYPE string,
        value TYPE string,
      END OF ty_property,
      ty_t_property TYPE STANDARD TABLE OF ty_property WITH EMPTY KEY.

    "! The repository of the server's data sources file, read once per session.
    CLASS-METHODS get
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_repository
      RAISING   zzxxmla1_cx_xmla.
    "! The repository of a data sources file (FileRepository.getServerInfo): its data sources in the order of the
    "! file; a catalog named twice in a data source is an error.
    CLASS-METHODS of_content
      IMPORTING !content      TYPE string
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_repository
      RAISING   zzxxmla1_cx_xmla.
    "! Util.parseConnectString: the pairs of a connect string ("Provider=olap4abap; Jdbc='a;b'").
    CLASS-METHODS parse_connect_string
      IMPORTING !text         TYPE string
      RETURNING VALUE(result) TYPE ty_t_property
      RAISING   zzxxmla1_cx_xmla.
    "! Util.PropertyList.toString: the pairs as a connect string, separated by "; ", a value with a semicolon quoted.
    CLASS-METHODS connect_string
      IMPORTING properties    TYPE ty_t_property
      RETURNING VALUE(result) TYPE string.
    "! The DataSourceInfo DISCOVER_DATASOURCES shows (Olap4jExtra.getDataSources): without Jdbc, JdbcUser and
    "! JdbcPassword, as written if it has none of them.
    CLASS-METHODS public_data_source_info
      IMPORTING data_source_info TYPE string
      RETURNING VALUE(result)    TYPE string
      RAISING   zzxxmla1_cx_xmla.

    "! The data sources in the order of the file.
    METHODS data_sources
      RETURNING VALUE(result) TYPE ty_t_data_source.
    "! The data source a client names in the DataSourceInfo property (FileRepository.getConnection): the one of that
    "! name, else the one whose connect string without Jdbc, JdbcUser and JdbcPassword is the name; without a name the
    "! first. Its name is initial if there is none.
    METHODS data_source
      IMPORTING !name         TYPE string
      RETURNING VALUE(result) TYPE ty_data_source
      RAISING   zzxxmla1_cx_xmla.
  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-DATA instance TYPE REF TO zzxxmla1_cl_repository.
    DATA all_data_sources TYPE ty_t_data_source.

    "! An error as the reference reports it in a SOAP fault.
    CLASS-METHODS fail
      IMPORTING !message TYPE string
      RAISING   zzxxmla1_cx_xmla.
    "! the connect string without the properties that hold the database's logon
    CLASS-METHODS without_jdbc
      CHANGING  properties    TYPE ty_t_property
      RETURNING VALUE(result) TYPE abap_bool.
    "! String.trim for spaces
    CLASS-METHODS trim
      IMPORTING !text         TYPE string
      RETURNING VALUE(result) TYPE string.
    "! PropertyList.put: a name already there (in any case) gets the new value, except Provider, whose first value stays.
    CLASS-METHODS put
      IMPORTING !name      TYPE string
                !value     TYPE string
      CHANGING  properties TYPE ty_t_property.
    CLASS-METHODS parse_data_sources
      IMPORTING !element      TYPE REF TO if_ixml_element
      RETURNING VALUE(result) TYPE ty_t_data_source
      RAISING   zzxxmla1_cx_xom.
    CLASS-METHODS parse_data_source
      IMPORTING !element      TYPE REF TO if_ixml_element
      RETURNING VALUE(result) TYPE ty_data_source
      RAISING   zzxxmla1_cx_xom.
    CLASS-METHODS parse_catalogs
      IMPORTING !element      TYPE REF TO if_ixml_element
      RETURNING VALUE(result) TYPE ty_t_catalog
      RAISING   zzxxmla1_cx_xom.
    CLASS-METHODS parse_catalog
      IMPORTING !element      TYPE REF TO if_ixml_element
      RETURNING VALUE(result) TYPE ty_catalog
      RAISING   zzxxmla1_cx_xom.
ENDCLASS.



CLASS zzxxmla1_cl_repository IMPLEMENTATION.

  METHOD get.
    IF instance IS NOT BOUND.
      DATA(file) = zzxxmla1_cl_files=>read( zzxxmla1_cl_files=>c_datasources ).
      IF file-path IS INITIAL.
        fail( |Internal error: the data sources file { zzxxmla1_cl_files=>c_datasources } does not exist| ).
      ENDIF.
      instance = of_content( file-content ).
    ENDIF.
    result = instance.
  ENDMETHOD.

  METHOD of_content.
    result = NEW #( ).
    DATA data_sources TYPE ty_t_data_source.
    TRY.
        data_sources = parse_data_sources( zzxxmla1_cl_xom_parser=>parse_document( content ) ).
      CATCH zzxxmla1_cx_xom INTO DATA(error).
        " XmlaSupport.parseDataSources adds the whole file to the message; the error and the file's name say enough
        fail( |Internal error: Failed to parse data sources config { zzxxmla1_cl_files=>c_datasources }: | &&
              error->error_message ).
    ENDTRY.
    LOOP AT data_sources INTO DATA(data_source).
      DATA(names) = VALUE string_table( ).
      LOOP AT data_source-catalogs INTO DATA(catalog).
        IF line_exists( names[ table_line = catalog-name ] ).
          fail( |Internal error: more than one DataSource object has name '{ catalog-name }'| ).
        ENDIF.
        APPEND catalog-name TO names.
      ENDLOOP.
      " datasourceMap.put: a later data source of the same name replaces the earlier
      READ TABLE result->all_data_sources WITH KEY name = data_source-name TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        MODIFY result->all_data_sources FROM data_source INDEX sy-tabix.
      ELSE.
        APPEND data_source TO result->all_data_sources.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD fail.
    zzxxmla1_cx_xmla=>raise_code( kind = `Server` code = `00HSBB01` text = `XMLA SOAP Body processing error`
                                  description = |olap4abap Error:{ message }| ).
  ENDMETHOD.

  METHOD data_sources.
    result = all_data_sources.
  ENDMETHOD.

  METHOD data_source.
    IF name IS INITIAL.
      READ TABLE all_data_sources INTO result INDEX 1.
      RETURN.
    ENDIF.
    READ TABLE all_data_sources INTO result WITH KEY name = name.
    IF sy-subrc = 0.
      RETURN.
    ENDIF.
    LOOP AT all_data_sources INTO DATA(candidate).
      DATA(properties) = parse_connect_string( candidate-data_source_info ).
      without_jdbc( CHANGING properties = properties ).
      IF connect_string( properties ) = name.
        result = candidate.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD public_data_source_info.
    DATA(properties) = parse_connect_string( data_source_info ).
    result = COND #( WHEN without_jdbc( CHANGING properties = properties ) = abap_true
                     THEN connect_string( properties )
                     ELSE data_source_info ).
  ENDMETHOD.

  METHOD without_jdbc.
    " PropertyList.remove: the names in any case
    LOOP AT properties INTO DATA(property).
      DATA(index) = sy-tabix.
      DATA(upper) = to_upper( property-name ).
      IF upper = `JDBC` OR upper = `JDBCUSER` OR upper = `JDBCPASSWORD`.
        DELETE properties INDEX index.
        result = abap_true.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD trim.
    result = replace( val = text regex = `^ +| +$` with = `` occ = 0 ).
  ENDMETHOD.

  METHOD put.
    LOOP AT properties ASSIGNING FIELD-SYMBOL(<property>).
      IF to_upper( <property>-name ) = to_upper( name ).
        IF to_upper( name ) <> `PROVIDER`.
          <property>-value = value.
        ENDIF.
        RETURN.
      ENDIF.
    ENDLOOP.
    APPEND VALUE #( name = name value = value ) TO properties.
  ENDMETHOD.

  METHOD parse_connect_string.
    " ConnectStringParser: name=value pairs separated by semicolons; a doubled = belongs to the name, a value may be
    " quoted with ' or " (the quote doubled inside), spaces around names and unquoted values are dropped
    DATA(n) = strlen( text ).
    DATA(i) = 0.
    WHILE i < n.
      " parseName
      DATA(name) = ``.
      DATA(has_name) = abap_false.
      WHILE has_name = abap_false.
        DATA(c) = substring( val = text off = i len = 1 ).
        IF c = `=`.
          i = i + 1.
          IF i < n AND substring( val = text off = i len = 1 ) = `=`.
            i = i + 1.
            name = name && `=`.
            CONTINUE.
          ENDIF.
          has_name = abap_true.
        ELSEIF c = ` ` AND name IS INITIAL.
          i = i + 1.
          IF i >= n.
            " no name, e.g. trailing spaces after a semicolon
            RETURN.
          ENDIF.
        ELSE.
          name = name && c.
          i = i + 1.
          IF i >= n.
            has_name = abap_true.
          ENDIF.
        ENDIF.
      ENDWHILE.
      name = trim( name ).
      " parseValue
      DATA(value) = ``.
      IF i < n AND substring( val = text off = i len = 1 ) = `;`.
        i = i + 1.
      ELSEIF i < n.
        WHILE i < n AND substring( val = text off = i len = 1 ) = ` `.
          i = i + 1.
        ENDWHILE.
        IF i < n.
          c = substring( val = text off = i len = 1 ).
          IF c = `"` OR c = `'`.
            " parseQuoted
            DATA(quote) = c.
            DATA(closed) = abap_false.
            i = i + 1.
            WHILE i < n AND closed = abap_false.
              c = substring( val = text off = i len = 1 ).
              i = i + 1.
              IF c <> quote.
                value = value && c.
              ELSEIF i < n AND substring( val = text off = i len = 1 ) = quote.
                value = value && c.
                i = i + 1.
              ELSE.
                closed = abap_true.
              ENDIF.
            ENDWHILE.
            IF closed = abap_false.
              fail( |Internal error: Connect string '{ text }' contains unterminated quoted value '{ value }'| ).
            ENDIF.
            WHILE i < n AND substring( val = text off = i len = 1 ) = ` `.
              i = i + 1.
            ENDWHILE.
            IF i < n.
              IF substring( val = text off = i len = 1 ) <> `;`.
                fail( |Internal error: quoted value ended too soon, at position { i } in '{ text }'| ).
              ENDIF.
              i = i + 1.
            ENDIF.
          ELSE.
            DATA(semicolon) = find( val = text sub = `;` off = i ).
            IF semicolon >= 0.
              value = substring( val = text off = i len = semicolon - i ).
              i = semicolon + 1.
            ELSE.
              value = substring( val = text off = i ).
              i = n.
            ENDIF.
            value = trim( value ).
          ENDIF.
        ENDIF.
      ENDIF.
      put( EXPORTING name = name value = value CHANGING properties = result ).
    ENDWHILE.
  ENDMETHOD.

  METHOD connect_string.
    LOOP AT properties INTO DATA(property).
      IF sy-tabix > 1.
        result = result && `; `.
      ENDIF.
      result = result && property-name && `=`.
      DATA(value) = property-value.
      IF value CA `;`.
        " quoted, the quotes inside doubled; a value that starts or ends with a quote keeps it as the quote
        DATA(last) = strlen( value ) - 1.
        DATA(first_char) = substring( val = value len = 1 ).
        DATA(last_char) = substring( val = value off = last len = 1 ).
        result = result && COND string( WHEN first_char <> `'` THEN `'` ) &&
                 replace( val = value sub = `'` with = `''` occ = 0 ) &&
                 COND string( WHEN last_char <> `'` THEN `'` ).
      ELSE.
        result = result && value.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD parse_data_sources.
    TRY.
        DATA(parser) = NEW zzxxmla1_cl_xom_parser( element ).
        LOOP AT parser->get_array( classes = VALUE #( ( `DataSource` ) )
                                   java_class = `olap4abap.DataSourcesConfig$DataSource`
                                   min = 0
                                   max = 0 ) INTO DATA(child).
          APPEND parse_data_source( child ) TO result.
        ENDLOOP.
      CATCH zzxxmla1_cx_xom INTO DATA(error).
        RAISE EXCEPTION TYPE zzxxmla1_cx_xom EXPORTING error_message = |In DataSources: { error->error_message }|.
    ENDTRY.
  ENDMETHOD.

  METHOD parse_data_source.
    TRY.
        DATA(parser) = NEW zzxxmla1_cl_xom_parser( element ).
        result-name = parser->get_string_element( name = `DataSourceName` required = abap_true ).
        result-description = parser->get_string_element( name = `DataSourceDescription` required = abap_true ).
        result-url = parser->get_string_element( name = `URL` required = abap_true ).
        result-data_source_info = parser->get_string_element( name = `DataSourceInfo` required = abap_true ).
        result-provider_name = parser->get_string_element( name = `ProviderName` required = abap_true ).
        result-provider_type = parser->get_string_element( name = `ProviderType` required = abap_true ).
        result-authentication_mode = parser->get_string_element( name = `AuthenticationMode` required = abap_true ).
        DATA(catalogs) = parser->get_element( classes = VALUE #( ( `Catalogs` ) )
                                              java_class = `olap4abap.DataSourcesConfig$Catalogs`
                                              required = abap_true ).
        IF catalogs IS BOUND.
          result-catalogs = parse_catalogs( catalogs ).
        ENDIF.
      CATCH zzxxmla1_cx_xom INTO DATA(error).
        RAISE EXCEPTION TYPE zzxxmla1_cx_xom EXPORTING error_message = |In DataSource: { error->error_message }|.
    ENDTRY.
  ENDMETHOD.

  METHOD parse_catalogs.
    TRY.
        DATA(parser) = NEW zzxxmla1_cl_xom_parser( element ).
        LOOP AT parser->get_array( classes = VALUE #( ( `Catalog` ) )
                                   java_class = `olap4abap.DataSourcesConfig$Catalog`
                                   min = 0
                                   max = 0 ) INTO DATA(child).
          APPEND parse_catalog( child ) TO result.
        ENDLOOP.
      CATCH zzxxmla1_cx_xom INTO DATA(error).
        RAISE EXCEPTION TYPE zzxxmla1_cx_xom EXPORTING error_message = |In Catalogs: { error->error_message }|.
    ENDTRY.
  ENDMETHOD.

  METHOD parse_catalog.
    TRY.
        DATA(parser) = NEW zzxxmla1_cl_xom_parser( element ).
        result-name = parser->get_string( name = `name` required = abap_true ).
        result-data_source_info = parser->get_string_element( `DataSourceInfo` ).
        result-definition = parser->get_string_element( name = `Definition` required = abap_true ).
      CATCH zzxxmla1_cx_xom INTO DATA(error).
        RAISE EXCEPTION TYPE zzxxmla1_cx_xom EXPORTING error_message = |In Catalog: { error->error_message }|.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
