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
CLASS zzxxmla1_cl_xmla_handler DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_result,
        status TYPE i,
        body   TYPE string,
      END OF ty_result.
    " What the client asked (see ZZXXMLA1_CL_XMLA_REQUEST): the RequestType, the Restrictions (filters on the rows) and
    " the Properties.
    TYPES ty_pair    TYPE zzxxmla1_cl_xmla_request=>ty_pair.
    TYPES ty_t_pair  TYPE zzxxmla1_cl_xmla_request=>ty_t_pair.
    TYPES ty_request TYPE zzxxmla1_cl_xmla_request=>ty_request.

    "! Handles one XMLA request: a SOAP envelope in, a SOAP envelope out. Knows nothing about HTTP, so it can be
    "! called from tests and from the ICF handler alike.
    "! @parameter request | the SOAP request body
    "! @parameter url | the URL clients use to reach this endpoint (DISCOVER_DATASOURCES of a data source without URL)
    METHODS handle
      IMPORTING request       TYPE string
                url           TYPE string
      RETURNING VALUE(result) TYPE ty_result.

  PRIVATE SECTION.
    CONSTANTS c_ns_xmla TYPE string VALUE `urn:schemas-microsoft-com:xml-analysis`.
    "! the data sources of the server and the schemas of their catalogs, read when a request is handled
    DATA repository TYPE REF TO zzxxmla1_cl_repository.
    DATA schema     TYPE REF TO zzxxmla1_cl_schema.
    "! the data source the request names in DataSourceInfo, else the first; its name is initial if it names none
    DATA data_source TYPE zzxxmla1_cl_repository=>ty_data_source.

    "! The answer to a checked request: the SOAP envelope of the rowset, or a fault.
    METHODS process
      IMPORTING request       TYPE ty_request
                url           TYPE string
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_xmla.
    "! What the reference checks of a Discover request before it answers: the request type is one of its rowsets, the
    "! restrictions are columns of that rowset, then the data source and the catalog exist.
    METHODS check_discover
      IMPORTING request TYPE ty_request
      RAISING   zzxxmla1_cx_xmla.
    "! SOAP fault document for an XMLA fault; HTTP status 200 as the reference answers faults.
    METHODS fault_result
      IMPORTING fault         TYPE REF TO zzxxmla1_cx_xmla
      RETURNING VALUE(result) TYPE ty_result.
    "! The catalogs of the request's data source, ascending.
    METHODS catalogs
      RETURNING VALUE(result) TYPE string_table.
    "! The reference's rule: the requested catalog if it exists, else (none requested) the first one, else empty.
    METHODS default_catalog
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string.
    METHODS discover_properties
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string.
    METHODS discover_schema_rowsets
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string.
    METHODS dbschema_catalogs
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string.
    METHODS mdschema_cubes
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string.
    METHODS mdschema_measures
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string.
    METHODS mdschema_dimensions
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string.
    METHODS mdschema_hierarchies
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string.
    METHODS mdschema_levels
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string.

    " A member as MDSCHEMA_MEMBERS lists it.
    TYPES:
      BEGIN OF ty_member,
        dimension    TYPE string,
        hierarchy    TYPE string,
        level        TYPE string,
        number       TYPE i,
        name         TYPE string,
        unique       TYPE string,
        type         TYPE i,
        cardinality  TYPE i,
        parent       TYPE string,
        parent_level TYPE i,
        parent_count TYPE i,
        depth        TYPE i,
      END OF ty_member,
      ty_t_member TYPE STANDARD TABLE OF ty_member WITH EMPTY KEY.
    METHODS mdschema_members
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string.
    METHODS static_rowset
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string.
    METHODS dbschema_schemata
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string.
    METHODS dbschema_tables_info
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string.
    METHODS dbschema_tables
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string.
    METHODS dbschema_columns
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string.
    METHODS mdschema_measuregroups
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string.
    METHODS measuregroup_dimensions
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string.
    "! MdschemaPropertiesRowset.populateImpl: the properties of the types in the PROPERTY_TYPE mask (default 1, member
    "! properties): for 1 the member properties of the levels (populateMember), for 2 the cell properties (olap4j's
    "! StandardCellProperty, populateCell; PROPERTY_NAME does not restrict them); system and blob properties none.
    METHODS mdschema_properties
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string.
    "! MdschemaPropertiesRowset.populateMember: the member properties of the levels of the cubes, in the order of the
    "! cube's dimensions, their hierarchies and levels; a LEVEL_UNIQUE_NAME restriction names the level, the dimension
    "! and hierarchy restrictions are not checked then (populateCube).
    METHODS member_properties
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string.
    "! The names of the levels of a hierarchy of the model, the (All) level first.
    METHODS levels_of
      IMPORTING dim           TYPE zzxxmla1_cl_schema=>ty_dim
                hier          TYPE zzxxmla1_cl_schema=>ty_hier
      RETURNING VALUE(result) TYPE string_table.
    "! The columns the reference shows for one level in DBSCHEMA_COLUMNS: name and OLE DB type of each; the (All) level has
    "! its NAME and UNIQUE_NAME twice, a level with a name column of its own the property $name (RolapLevel).
    METHODS level_columns
      IMPORTING prefix        TYPE string
                all_level     TYPE abap_bool
                has_name      TYPE abap_bool DEFAULT abap_false
                properties    TYPE zzxxmla1_cl_schema=>ty_t_property OPTIONAL
      RETURNING VALUE(result) TYPE ty_t_pair.
    TYPES ty_t_cube TYPE zzxxmla1_cl_schema=>ty_t_cube.
    "! The cubes of the model that the request selects by its catalog and cube restrictions (named by the two column
    "! names, which differ between the rowsets) and by the Catalog property.
    METHODS selected_cubes
      IMPORTING request        TYPE ty_request
                catalog_column TYPE string DEFAULT `CATALOG_NAME`
                cube_column    TYPE string DEFAULT `CUBE_NAME`
      RETURNING VALUE(result)  TYPE ty_t_cube.
    "! The members of one hierarchy of the model in hierarchy order: the All member if it has one, then the members
    "! read from the dimension table (ZZXXMLA1_CL_MODEL=>MEMBERS).
    METHODS hierarchy_members
      IMPORTING dim           TYPE zzxxmla1_cl_schema=>ty_dim
                hier          TYPE zzxxmla1_cl_schema=>ty_hier
      RETURNING VALUE(result) TYPE ty_t_member.
    "! The hierarchy of the model with the given names.
    METHODS model_hierarchy
      IMPORTING cube          TYPE clike
                dim           TYPE clike
                hier          TYPE clike
      RETURNING VALUE(result) TYPE zzxxmla1_cl_model=>ty_hierarchy
      RAISING   zzxxmla1_cx_xmla.
    "! The unique name of a hierarchy's default member (RolapHierarchy.init): its defaultMember, else the All member,
    "! else the first member.
    METHODS default_member
      IMPORTING hierarchy     TYPE zzxxmla1_cl_model=>ty_hierarchy
      RETURNING VALUE(result) TYPE string.
    "! The measures of a cube as members of the Measures hierarchy, in the order of the BW cube.
    METHODS measure_members
      IMPORTING cube          TYPE string
      RETURNING VALUE(result) TYPE ty_t_member.
    "! The members the restrictions ask for: filters on level, name and unique name, and the tree operation
    "! (TREE_OP: 1 children, 2 siblings, 4 parent, 8 self, 16 descendants, 32 ancestors, added together) relative to
    "! the member of MEMBER_UNIQUE_NAME.
    METHODS select_members
      IMPORTING request       TYPE ty_request
                members       TYPE ty_t_member
      RETURNING VALUE(result) TYPE ty_t_member.
    "! RowsetDefinition.MdschemaMembersRowset.populateMember: the member and, as the tree operation asks, its
    "! siblings, its children or descendants, its parent or ancestors.
    METHODS populate_member
      IMPORTING members TYPE ty_t_member
                member  TYPE ty_member
                tree_op TYPE i
      CHANGING  result  TYPE ty_t_member.
    "! One row of MDSCHEMA_LEVELS.
    METHODS level_xml
      IMPORTING catalog         TYPE clike
                cube            TYPE clike
                dimension       TYPE clike
                hierarchy_name  TYPE clike
                hierarchy_unique TYPE clike
                level_name      TYPE clike
                number          TYPE i
                cardinality     TYPE i
                type            TYPE i
                unique_settings TYPE i
      RETURNING VALUE(result)   TYPE string.
    "! LEVEL_TYPE of a level of the model (RowsetDefinition.MdschemaLevelsRowset.getLevelType): MDLEVEL_TYPE_TIME_*
    "! for a time level type, 0 (MDLEVEL_TYPE_REGULAR) else.
    CLASS-METHODS level_type_code
      IMPORTING level_type    TYPE string
      RETURNING VALUE(result) TYPE i.
    "! DIMENSION_TYPE of a dimension of the model: MD_DIMTYPE_TIME (1) or MD_DIMTYPE_OTHER (3).
    CLASS-METHODS dimension_type_code
      IMPORTING dim_type      TYPE string
      RETURNING VALUE(result) TYPE i.
    "! MDX unique name of a hierarchy: [Dimension] for the dimension's hierarchy, [Dimension.Hierarchy] for the others.
    METHODS hierarchy_unique_name
      IMPORTING dim_name      TYPE clike
                hier_name     TYPE clike
      RETURNING VALUE(result) TYPE string.
    "! Unique names of the bottom level of each hierarchy of a cube (dimensions, then hierarchies in model order),
    "! comma separated.
    METHODS levels_list
      IMPORTING cube          TYPE string
      RETURNING VALUE(result) TYPE string.
    "! True if the request has no restriction of that name, or one of its values equals the given one.
    METHODS is_allowed
      IMPORTING request       TYPE ty_request
                restriction   TYPE string
                value         TYPE clike
      RETURNING VALUE(result) TYPE abap_bool.
    "! One rowset row: an element per column, in the given order; an empty value gives an empty element.
    METHODS row_xml
      IMPORTING columns       TYPE ty_t_pair
      RETURNING VALUE(result) TYPE string.
    "! A timestamp as the reference writes it, yyyy-MM-ddTHH:mm:ss.
    METHODS timestamp_xml
      IMPORTING timestamp     TYPE timestampl
      RETURNING VALUE(result) TYPE string.
    METHODS discover_datasources
      IMPORTING url           TYPE string
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_xmla.
    "! The answer of a Discover request: the rowset's xsd:schema for Content Schema and SchemaData (the default), the
    "! rows for Data and SchemaData (XmlaHandler.discover).
    METHODS discover_response
      IMPORTING request       TYPE ty_request
                rows          TYPE string
      RETURNING VALUE(result) TYPE string.
    "! The answer of an Execute request without statement: an empty root, as the reference gives it.
    METHODS empty_execute_response
      RETURNING VALUE(result) TYPE string.
    "! The response body with the Session header element of the request's session, if it has one.
    METHODS with_session
      IMPORTING body          TYPE string
                request       TYPE ty_request
      RETURNING VALUE(result) TYPE string.
    METHODS xml_text
      IMPORTING value         TYPE string
      RETURNING VALUE(result) TYPE string.
ENDCLASS.



CLASS zzxxmla1_cl_xmla_handler IMPLEMENTATION.

  METHOD handle.
    TRY.
        DATA(parsed) = zzxxmla1_cl_xmla_request=>parse( request ).
      CATCH zzxxmla1_cx_xmla INTO DATA(fault).
        result = fault_result( fault ).
        RETURN.
    ENDTRY.
    TRY.
        repository = zzxxmla1_cl_repository=>get( ).
        schema = zzxxmla1_cl_schema=>get( ).
        data_source = repository->data_source( VALUE #( parsed-properties[ name = 'DataSourceInfo' ]-value OPTIONAL ) ).
        result = VALUE #( status = 200 body = process( request = parsed url = url ) ).
      CATCH zzxxmla1_cx_xmla INTO fault.
        result = fault_result( fault ).
      CATCH zzxxmla1_cx_sql INTO DATA(sql_error).
        " a failed statement is the reference's internal error
        result = fault_result( zzxxmla1_cx_xmla=>of_code(
          kind = `Server` code = `00UE001` text = `Internal Error`
          description = |olap4abap Error:Internal error: { sql_error->get_text( ) }| ) ).
    ENDTRY.
    result-body = with_session( body = result-body request = parsed ).
  ENDMETHOD.

  METHOD with_session.
    " The reference answers a session header element with the session: a new id for BeginSession, the client's for Session
    " and EndSession. Nothing is stored (see ZZXXMLA1_CL_XMLA_REQUEST=>CHECK_HEADER), so a new id is just unique.
    result = body.
    DATA(session_id) = request-session_id.
    CASE request-session_state.
      WHEN `BEGIN`.
        TRY.
            session_id = to_lower( cl_system_uuid=>create_uuid_c32_static( ) ).
          CATCH cx_uuid_error.
            session_id = |{ sy-datum }{ sy-uzeit }|.
        ENDTRY.
      WHEN `WITHIN` OR `END`.
      WHEN OTHERS.
        RETURN.
    ENDCASE.
    result = replace(
      val  = body
      sub  = `<SOAP-ENV:Header>` && cl_abap_char_utilities=>newline && `</SOAP-ENV:Header>`
      with = `<SOAP-ENV:Header>` && cl_abap_char_utilities=>newline &&
             `<Session SessionId="` && escape( val = session_id format = cl_abap_format=>e_xml_attr ) &&
             `" xmlns="` && c_ns_xmla && `" /></SOAP-ENV:Header>` ).
  ENDMETHOD.

  METHOD process.
    " Execute is not implemented yet: only the data source is checked, as the reference does when it processes the body
    IF request-method = `EXECUTE`.
      DATA(database) = VALUE string( request-properties[ name = 'DataSourceInfo' ]-value OPTIONAL ).
      IF data_source-name IS INITIAL.
        zzxxmla1_cx_xmla=>raise_code(
          kind = `Server` code = `00HSBB01` text = `XMLA SOAP Body processing error`
          description = |olap4abap Error:Internal error: Unknown database '{ database }'| ).
      ENDIF.
      IF line_exists( request-properties[ name = 'Catalog' ] ).
        DATA(requested_catalog) = request-properties[ name = 'Catalog' ]-value.
        DATA(known) = catalogs( ).
        IF NOT line_exists( known[ table_line = requested_catalog ] ).
          zzxxmla1_cx_xmla=>raise_code(
            kind = `Server` code = `00HSBB01` text = `XMLA SOAP Body processing error`
            description = |olap4abap Error:Internal error: Unknown catalog '{ requested_catalog }'| ).
        ENDIF.
      ENDIF.
      IF request-statement IS INITIAL.
        " no statement (Excel opens its session so): an empty answer, as the reference gives
        result = empty_execute_response( ).
        RETURN.
      ENDIF.
      DATA(statement) = zzxxmla1_cl_mdx_parser=>parse( request-statement ).
      IF statement-kind <> `SELECT`.
        zzxxmla1_cx_xmla=>raise_code(
          kind = `Server` code = `00HSBB01` text = `XMLA SOAP Body processing error`
          description = |olap4abap Error:{ statement-kind } statements are not implemented yet| ).
      ENDIF.
      DATA(query) = statement-query.
      DATA(engine) = NEW zzxxmla1_cl_mdx_engine( default_catalog( request ) ).
      DATA(content) = VALUE string( request-properties[ name = 'Content' ]-value OPTIONAL ).
      result = zzxxmla1_cl_xmla_mddataset=>build(
        result      = engine->execute( query )
        with_schema = xsdbool( content IS INITIAL OR content = `SchemaData` OR content = `Schema` ) ).
      RETURN.
    ENDIF.

    check_discover( request ).
    DATA rows TYPE string.
    CASE request-type.
      WHEN 'DISCOVER_DATASOURCES'.
        rows = discover_datasources( url ).
      WHEN 'DISCOVER_PROPERTIES'.
        rows = discover_properties( request ).
      WHEN 'DISCOVER_SCHEMA_ROWSETS'.
        rows = discover_schema_rowsets( request ).
      WHEN 'DBSCHEMA_CATALOGS'.
        rows = dbschema_catalogs( request ).
      WHEN 'MDSCHEMA_CUBES'.
        rows = mdschema_cubes( request ).
      WHEN 'MDSCHEMA_MEASURES'.
        rows = mdschema_measures( request ).
      WHEN 'MDSCHEMA_DIMENSIONS'.
        rows = mdschema_dimensions( request ).
      WHEN 'MDSCHEMA_HIERARCHIES'.
        rows = mdschema_hierarchies( request ).
      WHEN 'MDSCHEMA_LEVELS'.
        rows = mdschema_levels( request ).
      WHEN 'MDSCHEMA_MEMBERS'.
        rows = mdschema_members( request ).
      WHEN 'DISCOVER_ENUMERATORS' OR 'DISCOVER_KEYWORDS' OR 'DISCOVER_LITERALS' OR 'DBSCHEMA_PROVIDER_TYPES' OR 'MDSCHEMA_FUNCTIONS'.
        rows = static_rowset( request ).
      WHEN 'DBSCHEMA_SCHEMATA'.
        rows = dbschema_schemata( request ).
      WHEN 'DBSCHEMA_TABLES_INFO'.
        rows = dbschema_tables_info( request ).
      WHEN 'DBSCHEMA_TABLES'.
        rows = dbschema_tables( request ).
      WHEN 'DBSCHEMA_COLUMNS'.
        rows = dbschema_columns( request ).
      WHEN 'MDSCHEMA_MEASUREGROUPS'.
        rows = mdschema_measuregroups( request ).
      WHEN 'MDSCHEMA_MEASUREGROUP_DIMENSIONS'.
        rows = measuregroup_dimensions( request ).
      WHEN 'DISCOVER_XML_METADATA' OR 'DISCOVER_SESSIONS' OR 'DBSCHEMA_SOURCE_TABLES'.
        " no rows: this server has no XML metadata objects, no sessions and no relational source tables to report.
        " (the reference lists its own sessions and the tables of its JDBC database here, which cannot be the same.)
        rows = ``.
      WHEN 'MDSCHEMA_PROPERTIES'.
        rows = mdschema_properties( request ).
      WHEN 'MDSCHEMA_SETS' OR 'MDSCHEMA_KPIS' OR 'MDSCHEMA_ACTIONS'.
        " Excel and other clients ask for these. The model has no named sets, KPIs or actions, so the answer is a correct
        " rowset without rows, as the reference gives for a schema without them.
        rows = ``.
      WHEN 'DISCOVER_CSDL_METADATA'.
        " The reference server answers this with a licence error of a module it does not ship; the same text is given here. Its
        " rows are only made when they are sent: Content Schema is the schema alone.
        IF VALUE string( request-properties[ name = 'Content' ]-value OPTIONAL ) <> `Schema`.
          RAISE EXCEPTION TYPE zzxxmla1_cx_xmla
            EXPORTING
              fault_code   = `SOAP-ENV:00UE001.Internal Error`
              fault_string = `SqlException: The olap4abap DAX module was not found. Or a proper license was not found. Details: olap4abap/dax/CsdlSchemaGenerator`
              description  = `The olap4abap DAX module was not found. Or a proper license was not found. Details: olap4abap/dax/CsdlSchemaGenerator`.
        ENDIF.
      WHEN OTHERS.
        " a rowset of the list that this server does not answer yet
        zzxxmla1_cx_xmla=>raise_code(
          kind = `Server` code = `00HSBB01` text = `XMLA SOAP Body processing error`
          description = |Rowset { request-type } is not implemented yet| ).
    ENDCASE.
    result = discover_response( request = request rows = rows ).
  ENDMETHOD.

  METHOD check_discover.
    " 1. the request type must be a rowset (the reference: RowsetDefinition.valueOf)
    DATA(rowsets) = zzxxmla1_cl_xmla_rowsets=>get_all( ).
    IF NOT line_exists( rowsets[ name = request-type ] ).
      zzxxmla1_cx_xmla=>raise_code(
        kind = `Server` code = `00HSBB01` text = `XMLA SOAP Body processing error`
        description = |No enum constant olap4abap.RowsetDefinition.{ request-type }| ).
    ENDIF.

    " 2. every restriction must be a column of the rowset that can be restricted
    DATA(columns) = VALUE string_table( ).
    SPLIT rowsets[ name = request-type ]-restrictions AT ` ` INTO TABLE DATA(items).
    LOOP AT items INTO DATA(item).
      SPLIT item AT `:` INTO DATA(column) DATA(xsd_type).
      APPEND column TO columns.
    ENDLOOP.
    LOOP AT request-restrictions INTO DATA(restriction).
      IF NOT line_exists( columns[ table_line = restriction-name ] ).
        zzxxmla1_cx_xmla=>raise_code(
          kind = `Server` code = `00HSBB01` text = `XMLA SOAP Body processing error`
          description = |olap4abap Error:Internal error: Rowset '{ request-type }' does not contain column '{ restriction-name }'| ).
      ENDIF.
    ENDLOOP.

    " 3. the data source and the catalog the client names must exist (a different fault code and error code)
    IF line_exists( request-properties[ name = 'DataSourceInfo' ] ).
      DATA(database) = request-properties[ name = 'DataSourceInfo' ]-value.
      IF data_source-name IS INITIAL.
        zzxxmla1_cx_xmla=>raise_code(
          kind = `Server` code = `00HSBE02` text = `XMLA Discover unparse results error`
          description = |olap4abap Error:Internal error: Unknown database '{ database }'| error_code = `3238789130` ).
      ENDIF.
    ENDIF.
    IF line_exists( request-properties[ name = 'Catalog' ] ).
      DATA(catalog) = request-properties[ name = 'Catalog' ]-value.
      DATA(known_catalogs) = catalogs( ).
      IF NOT line_exists( known_catalogs[ table_line = catalog ] ).
        zzxxmla1_cx_xmla=>raise_code(
          kind = `Server` code = `00HSBE02` text = `XMLA Discover unparse results error`
          description = |olap4abap Error:Internal error: Unknown catalog '{ catalog }'| error_code = `3238789130` ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD fault_result.
    result-status = 200.
    result-body =
      `<?xml version="1.0" encoding="UTF-8"?>` && cl_abap_char_utilities=>newline &&
      `<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">` && cl_abap_char_utilities=>newline &&
      `<SOAP-ENV:Header>` && cl_abap_char_utilities=>newline &&
      `</SOAP-ENV:Header>` && cl_abap_char_utilities=>newline &&
      `<SOAP-ENV:Body>` && cl_abap_char_utilities=>newline &&
      `<SOAP-ENV:Fault>` && cl_abap_char_utilities=>newline &&
      `  <faultcode>` && xml_text( fault->fault_code ) && `</faultcode>` && cl_abap_char_utilities=>newline &&
      `  <faultstring>` && xml_text( fault->fault_string ) && `</faultstring>` && cl_abap_char_utilities=>newline &&
      `  <faultactor>olap4abap</faultactor>` && cl_abap_char_utilities=>newline &&
      `  <detail>` && cl_abap_char_utilities=>newline &&
      `    <Error ErrorCode="` && fault->error_code && `" Description="` &&
        escape( val = |The olap4abap XML: { fault->description }| format = cl_abap_format=>e_xml_attr ) && `"/>` && cl_abap_char_utilities=>newline &&
      `  </detail>` && cl_abap_char_utilities=>newline &&
      `</SOAP-ENV:Fault>` && cl_abap_char_utilities=>newline &&
      `</SOAP-ENV:Body>` && cl_abap_char_utilities=>newline &&
      `</SOAP-ENV:Envelope>` && cl_abap_char_utilities=>newline.
  ENDMETHOD.

  METHOD catalogs.
    LOOP AT schema->catalogs( ) INTO DATA(catalog).
      IF line_exists( data_source-catalogs[ name = catalog ] ).
        APPEND catalog TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD default_catalog.
    DATA(known) = catalogs( ).
    IF line_exists( request-properties[ name = 'Catalog' ] ).
      DATA(wanted) = request-properties[ name = 'Catalog' ]-value.
      IF line_exists( known[ table_line = wanted ] ).
        result = wanted.
      ENDIF.
    ELSEIF known IS NOT INITIAL.
      result = known[ 1 ].
    ENDIF.
  ENDMETHOD.

  METHOD discover_properties.
    " one row per property definition, optionally restricted by PropertyName (as in DiscoverPropertiesRowset)
    LOOP AT zzxxmla1_cl_xmla_propdef=>get_all( ) INTO DATA(definition).
      IF is_allowed( request = request restriction = `PropertyName` value = definition-name ) = abap_false.
        CONTINUE.
      ENDIF.
      DATA(value) = COND string( WHEN definition-name = 'Catalog' THEN default_catalog( request ) ELSE definition-default_value ).
      result = result && row_xml( VALUE #(
        ( name = `PropertyName`       value = definition-name )
        ( name = `PropertyDescription` value = definition-description )
        ( name = `PropertyType`       value = definition-data_type )
        ( name = `PropertyAccessType` value = definition-access )
        ( name = `IsRequired`         value = `false` )
        ( name = `Value`              value = value ) ) ).
    ENDLOOP.
  ENDMETHOD.

  METHOD discover_schema_rowsets.
    " one row per rowset this server lists (static, see ZZXXMLA1_CL_XMLA_ROWSETS), optionally restricted by SchemaName
    LOOP AT zzxxmla1_cl_xmla_rowsets=>get_all( ) INTO DATA(rowset).
      IF is_allowed( request = request restriction = `SchemaName` value = rowset-name ) = abap_false.
        CONTINUE.
      ENDIF.
      DATA(restrictions) = VALUE string( ).
      SPLIT rowset-restrictions AT ` ` INTO TABLE DATA(items).
      LOOP AT items INTO DATA(item).
        SPLIT item AT `:` INTO DATA(column) DATA(xsd_type).
        restrictions = restrictions &&
          `        <Restrictions>` && cl_abap_char_utilities=>newline &&
          `          <Name>` && xml_text( column ) && `</Name>` && cl_abap_char_utilities=>newline &&
          `          <Type>xsd:` && xml_text( xsd_type ) && `</Type>` && cl_abap_char_utilities=>newline &&
          `        </Restrictions>` && cl_abap_char_utilities=>newline.
      ENDLOOP.
      result = result &&
        `      <row>` && cl_abap_char_utilities=>newline &&
        `        <SchemaName>` && xml_text( rowset-name ) && `</SchemaName>` && cl_abap_char_utilities=>newline &&
        `        <SchemaGuid>` && xml_text( rowset-guid ) && `</SchemaGuid>` && cl_abap_char_utilities=>newline &&
        restrictions &&
        `        <Description>` && xml_text( rowset-description ) && `</Description>` && cl_abap_char_utilities=>newline &&
        COND string( WHEN rowset-mask IS NOT INITIAL
                     THEN `        <RestrictionsMask>` && rowset-mask && `</RestrictionsMask>` && cl_abap_char_utilities=>newline ) &&
        `      </row>` && cl_abap_char_utilities=>newline.
    ENDLOOP.
  ENDMETHOD.

  METHOD dbschema_catalogs.
    " all catalogs, filtered only by the CATALOG_NAME restriction (the Catalog property does not filter this rowset)
    DATA now TYPE timestampl.
    LOOP AT catalogs( ) INTO DATA(catalog).
      IF is_allowed( request = request restriction = `CATALOG_NAME` value = catalog ) = abap_false.
        CONTINUE.
      ENDIF.
      GET TIME STAMP FIELD now.
      result = result && row_xml( VALUE #(
        ( name = `CATALOG_NAME`        value = catalog )
        ( name = `DESCRIPTION`         value = `No description available` )
        ( name = `ROLES`               value = `` )
        ( name = `DATE_MODIFIED`       value = timestamp_xml( now ) )
        ( name = `COMPATIBILITY_LEVEL` value = `1100` ) ) ).
    ENDLOOP.
  ENDMETHOD.

  METHOD mdschema_cubes.
    " one row per cube of the model; the catalog is the cube's InfoArea and also serves as its schema name
    DATA(cubes) = schema->cubes( ).
    DATA(wanted_catalog) = VALUE string( request-properties[ name = 'Catalog' ]-value OPTIONAL ).
    DATA now TYPE timestampl.
    LOOP AT cubes INTO DATA(cube).
      IF ( wanted_catalog IS NOT INITIAL AND cube-catalog_name <> wanted_catalog )
          OR is_allowed( request = request restriction = `CATALOG_NAME` value = cube-catalog_name ) = abap_false
          OR is_allowed( request = request restriction = `SCHEMA_NAME` value = cube-catalog_name ) = abap_false
          OR is_allowed( request = request restriction = `CUBE_NAME` value = cube-cube_name ) = abap_false.
        CONTINUE.
      ENDIF.
      GET TIME STAMP FIELD now.
      result = result && row_xml( VALUE #(
        ( name = `CATALOG_NAME`            value = cube-catalog_name )
        ( name = `SCHEMA_NAME`             value = cube-catalog_name )
        ( name = `CUBE_NAME`               value = cube-cube_name )
        ( name = `CUBE_TYPE`               value = `CUBE` )
        ( name = `LAST_SCHEMA_UPDATE`      value = timestamp_xml( cube-generated_at ) )
        ( name = `LAST_DATA_UPDATE`        value = timestamp_xml( now ) )
        ( name = `DESCRIPTION`             value = |{ cube-catalog_name } Schema - { cube-cube_name } Cube| )
        ( name = `IS_DRILLTHROUGH_ENABLED` value = `true` )
        ( name = `IS_LINKABLE`             value = `false` )
        ( name = `IS_WRITE_ENABLED`        value = `false` )
        ( name = `IS_SQL_ENABLED`          value = `false` )
        ( name = `CUBE_CAPTION`            value = cube-caption )
        ( name = `CUBE_SOURCE`             value = `1` ) ) ).
    ENDLOOP.
  ENDMETHOD.

  METHOD hierarchy_unique_name.
    result = zzxxmla1_cl_model=>hierarchy_unique_name( dim_name = dim_name hier_name = hier_name ).
  ENDMETHOD.

  METHOD levels_list.
    " model order: dimensions by seq_no, their hierarchies by seq_no; of each hierarchy its bottom level
    LOOP AT schema->dimensions( cube ) INTO DATA(dim).
      LOOP AT schema->hierarchies( cube = cube dim = dim-dim_name ) INTO DATA(hier).
        DATA(levels) = schema->levels( cube = cube dim = dim-dim_name hier = hier-hier_name ).
        IF levels IS NOT INITIAL.
          DATA(level) = levels[ lines( levels ) ].
          result = result && COND string( WHEN result IS NOT INITIAL THEN `,` ) &&
                   |{ hierarchy_unique_name( dim_name = level-dim_name hier_name = level-hier_name ) }.[{ level-level_name }]|.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD mdschema_measures.
    " one row per measure of each cube of the model, in name order as the reference lists them
    DATA(cubes) = schema->cubes( ).
    DATA(measures) = VALUE zzxxmla1_cl_schema=>ty_t_measure( ).
    LOOP AT cubes INTO DATA(measure_cube).
      APPEND LINES OF schema->measures( measure_cube-cube_name ) TO measures.
    ENDLOOP.
    SORT measures BY cube_name ASCENDING meas_name ASCENDING.
    DATA(wanted_catalog) = VALUE string( request-properties[ name = 'Catalog' ]-value OPTIONAL ).
    LOOP AT measures INTO DATA(measure).
      DATA(catalog) = cubes[ cube_name = measure-cube_name ]-catalog_name.
      DATA(unique_name) = |[Measures].[{ measure-meas_name }]|.
      IF ( wanted_catalog IS NOT INITIAL AND catalog <> wanted_catalog )
          OR is_allowed( request = request restriction = `CATALOG_NAME` value = catalog ) = abap_false
          OR is_allowed( request = request restriction = `SCHEMA_NAME` value = catalog ) = abap_false
          OR is_allowed( request = request restriction = `CUBE_NAME` value = measure-cube_name ) = abap_false
          OR is_allowed( request = request restriction = `MEASURE_NAME` value = measure-meas_name ) = abap_false
          OR is_allowed( request = request restriction = `MEASURE_UNIQUE_NAME` value = unique_name ) = abap_false.
        CONTINUE.
      ENDIF.
      " MDMEASURE_AGGR_* of the OLE DB for OLAP specification; sum is the only aggregator the model has so far
      DATA(aggregator) = SWITCH string( measure-aggregator WHEN 'sum' THEN `1` WHEN 'count' THEN `2` WHEN 'min' THEN `3`
                                                           WHEN 'max' THEN `4` WHEN 'avg' THEN `5` ELSE `127` ).
      DATA(columns) = VALUE ty_t_pair(
        ( name = `CATALOG_NAME`         value = catalog )
        ( name = `SCHEMA_NAME`          value = catalog )
        ( name = `CUBE_NAME`            value = measure-cube_name )
        ( name = `MEASURE_NAME`         value = measure-meas_name )
        ( name = `MEASURE_UNIQUE_NAME`  value = unique_name )
        ( name = `MEASURE_CAPTION`      value = measure-caption )
        ( name = `MEASURE_AGGREGATOR`   value = aggregator )
        ( name = `DATA_TYPE`            value = `5` )
        ( name = `MEASURE_IS_VISIBLE`   value = COND #( WHEN measure-visible = 'X' THEN `true` ELSE `false` ) )
        ( name = `LEVELS_LIST`          value = levels_list( measure-cube_name ) )
        ( name = `DESCRIPTION`          value = |{ measure-cube_name } Cube - { measure-meas_name } Member| )
        ( name = `MEASUREGROUP_NAME`    value = measure-cube_name )
        ( name = `MEASURE_DISPLAY_FOLDER` value = `` ) ).
      IF measure-format_string IS NOT INITIAL.
        APPEND VALUE #( name = `DEFAULT_FORMAT_STRING` value = measure-format_string ) TO columns.
      ENDIF.
      APPEND VALUE #( name = `MEASURE_VISIBILITY` value = COND #( WHEN measure-visible = 'X' THEN `1` ELSE `0` ) ) TO columns.
      result = result && row_xml( columns ).
    ENDLOOP.
  ENDMETHOD.

  METHOD mdschema_dimensions.
    " The dimensions of a cube as the reference lists them: the Measures pseudo-dimension (ordinal 0) and the dimensions of
    " the model (ordinal = position in the cube + 1), sorted by name. The cardinality is the number of members of the
    " bottom level of the dimension's first hierarchy plus one (MdschemaDimensionsRowset), counted in the database.
    TYPES: BEGIN OF ty_line,
             name TYPE string,
             xml  TYPE string,
           END OF ty_line.
    TYPES: BEGIN OF ty_dimension,
             name        TYPE string,
             ordinal     TYPE i,
             type        TYPE i,
             cardinality TYPE i,
             default     TYPE string,
           END OF ty_dimension,
           ty_t_dimension TYPE STANDARD TABLE OF ty_dimension WITH EMPTY KEY.
    DATA lines TYPE STANDARD TABLE OF ty_line WITH EMPTY KEY.
    DATA(wanted_catalog) = VALUE string( request-properties[ name = 'Catalog' ]-value OPTIONAL ).

    DATA(cubes) = schema->cubes( ).
    LOOP AT cubes INTO DATA(cube).
      IF ( wanted_catalog IS NOT INITIAL AND cube-catalog_name <> wanted_catalog )
          OR is_allowed( request = request restriction = `CATALOG_NAME` value = cube-catalog_name ) = abap_false
          OR is_allowed( request = request restriction = `SCHEMA_NAME` value = cube-catalog_name ) = abap_false
          OR is_allowed( request = request restriction = `CUBE_NAME` value = cube-cube_name ) = abap_false.
        CONTINUE.
      ENDIF.

      DATA(measure_count) = lines( schema->measures( cube-cube_name ) ).
      DATA(dims) = schema->dimensions( cube-cube_name ).

      " The reference counts two more members than there are measures
      DATA(dimensions) = VALUE ty_t_dimension(
        ( name = `Measures` ordinal = 0 type = 2 cardinality = measure_count + 2 default = `[Measures]` ) ).
      LOOP AT dims INTO DATA(dim).
        DATA(first_hierarchies) = schema->hierarchies( cube = cube-cube_name dim = dim-dim_name ).
        DATA(first_hierarchy) = VALUE string( first_hierarchies[ 1 ]-hier_name OPTIONAL ).
        DATA(first_model) = model_hierarchy( cube = cube-cube_name dim = dim-dim_name hier = first_hierarchy ).
        APPEND VALUE #( name = dim-dim_name ordinal = dim-seq_no type = dimension_type_code( dim-dim_type )
                        cardinality = zzxxmla1_cl_model=>level_cardinality( hierarchy = first_model
                                                                            level_no  = lines( first_model-levels ) ) + 1
                        default = hierarchy_unique_name( dim_name = dim-dim_name hier_name = first_hierarchy ) )
               TO dimensions.
      ENDLOOP.

      LOOP AT dimensions INTO DATA(dimension).
        IF is_allowed( request = request restriction = `DIMENSION_NAME` value = dimension-name ) = abap_false
            OR is_allowed( request = request restriction = `DIMENSION_UNIQUE_NAME` value = |[{ dimension-name }]| ) = abap_false.
          CONTINUE.
        ENDIF.
        APPEND VALUE #( name = dimension-name
                        xml  = row_xml( VALUE #(
          ( name = `CATALOG_NAME`             value = cube-catalog_name )
          ( name = `SCHEMA_NAME`              value = cube-catalog_name )
          ( name = `CUBE_NAME`                value = cube-cube_name )
          ( name = `DIMENSION_NAME`           value = dimension-name )
          ( name = `DIMENSION_UNIQUE_NAME`    value = |[{ dimension-name }]| )
          ( name = `DIMENSION_CAPTION`        value = dimension-name )
          ( name = `DIMENSION_ORDINAL`        value = |{ dimension-ordinal }| )
          ( name = `DIMENSION_TYPE`           value = |{ dimension-type }| )
          ( name = `DIMENSION_CARDINALITY`    value = |{ dimension-cardinality }| )
          ( name = `DEFAULT_HIERARCHY`        value = dimension-default )
          ( name = `DESCRIPTION`              value = |{ cube-cube_name } Cube - { dimension-name } Dimension| )
          ( name = `IS_VIRTUAL`               value = `false` )
          ( name = `IS_READWRITE`             value = `false` )
          ( name = `DIMENSION_UNIQUE_SETTINGS` value = `0` )
          ( name = `DIMENSION_IS_VISIBLE`     value = `true` ) ) ) ) TO lines.
      ENDLOOP.
    ENDLOOP.

    SORT lines BY name ASCENDING.
    LOOP AT lines INTO DATA(line).
      result = result && line-xml.
    ENDLOOP.
  ENDMETHOD.

  METHOD mdschema_hierarchies.
    " The hierarchies of a cube as the reference lists them: Measures (ordinal 0) and every hierarchy of the model (ordinal =
    " running number in model order), sorted by name. A hierarchy's name is Dimension.Hierarchy, the dimension's
    " hierarchy's name is the dimension's. The cardinality is the sum of the cardinalities of its levels, plus one
    " for the All member.
    TYPES: BEGIN OF ty_line,
             name TYPE string,
             xml  TYPE string,
           END OF ty_line.
    DATA lines TYPE STANDARD TABLE OF ty_line WITH EMPTY KEY.
    DATA(wanted_catalog) = VALUE string( request-properties[ name = 'Catalog' ]-value OPTIONAL ).

    DATA(cubes) = schema->cubes( ).
    LOOP AT cubes INTO DATA(cube).
      IF ( wanted_catalog IS NOT INITIAL AND cube-catalog_name <> wanted_catalog )
          OR is_allowed( request = request restriction = `CATALOG_NAME` value = cube-catalog_name ) = abap_false
          OR is_allowed( request = request restriction = `SCHEMA_NAME` value = cube-catalog_name ) = abap_false
          OR is_allowed( request = request restriction = `CUBE_NAME` value = cube-cube_name ) = abap_false.
        CONTINUE.
      ENDIF.

      DATA(measures) = schema->measures( cube-cube_name ).
      IF is_allowed( request = request restriction = `DIMENSION_UNIQUE_NAME` value = `[Measures]` ) = abap_true
          AND is_allowed( request = request restriction = `HIERARCHY_NAME` value = `Measures` ) = abap_true
          AND is_allowed( request = request restriction = `HIERARCHY_UNIQUE_NAME` value = `[Measures]` ) = abap_true.
        APPEND VALUE #( name = `Measures`
                        xml  = row_xml( VALUE #(
          ( name = `CATALOG_NAME`             value = cube-catalog_name )
          ( name = `SCHEMA_NAME`              value = cube-catalog_name )
          ( name = `CUBE_NAME`                value = cube-cube_name )
          ( name = `DIMENSION_UNIQUE_NAME`    value = `[Measures]` )
          ( name = `HIERARCHY_NAME`           value = `Measures` )
          ( name = `HIERARCHY_UNIQUE_NAME`    value = `[Measures]` )
          ( name = `HIERARCHY_CAPTION`        value = `Measures` )
          ( name = `DIMENSION_TYPE`           value = `2` )
          ( name = `HIERARCHY_CARDINALITY`    value = |{ lines( measures ) + 1 }| )
          ( name = `DEFAULT_MEMBER`           value = COND #( WHEN measures IS NOT INITIAL THEN |[Measures].[{ measures[ 1 ]-meas_name }]| ) )
          ( name = `DESCRIPTION`              value = |{ cube-cube_name } Cube - Measures Hierarchy| )
          ( name = `STRUCTURE`                value = `0` )
          ( name = `IS_VIRTUAL`               value = `false` )
          ( name = `IS_READWRITE`             value = `false` )
          ( name = `DIMENSION_UNIQUE_SETTINGS` value = `0` )
          ( name = `DIMENSION_IS_VISIBLE`     value = `true` )
          ( name = `HIERARCHY_ORDINAL`        value = `0` )
          ( name = `DIMENSION_IS_SHARED`      value = `true` )
          ( name = `HIERARCHY_IS_VISIBLE`     value = `true` )
          ( name = `HIERARCHY_ORIGIN`         value = `6` )
          ( name = `HIERARCHY_DISPLAY_FOLDER` value = `` )
          ( name = `HIERARCHY_VISIBILITY`     value = `1` )
          ( name = `PARENT_CHILD`             value = `false` ) ) ) ) TO lines.
      ENDIF.

      DATA(dims) = schema->dimensions( cube-cube_name ).
      DATA ordinal TYPE i.
      ordinal = 0.
      LOOP AT dims INTO DATA(dim).
        DATA(hiers) = schema->hierarchies( cube = cube-cube_name dim = dim-dim_name ).
        LOOP AT hiers INTO DATA(hier).
          ordinal = ordinal + 1.
          DATA(hier_name) = hier-name.
          DATA(unique_name) = hierarchy_unique_name( dim_name = dim-dim_name hier_name = hier-hier_name ).
          IF is_allowed( request = request restriction = `DIMENSION_UNIQUE_NAME` value = |[{ dim-dim_name }]| ) = abap_false
              OR is_allowed( request = request restriction = `HIERARCHY_NAME` value = hier_name ) = abap_false
              OR is_allowed( request = request restriction = `HIERARCHY_UNIQUE_NAME` value = unique_name ) = abap_false.
            CONTINUE.
          ENDIF.

          DATA(model) = model_hierarchy( cube = cube-cube_name dim = dim-dim_name hier = hier-hier_name ).
          DATA(cardinality) = COND i( WHEN hier-has_all = abap_true THEN 1 ).
          DO lines( model-levels ) TIMES.
            cardinality = cardinality + zzxxmla1_cl_model=>level_cardinality( hierarchy = model level_no = sy-index ).
          ENDDO.
          DATA(all_member) = |{ unique_name }.{ zzxxmla1_cl_model=>quote_name( hier-all_member_name ) }|.
          DATA(columns) = VALUE ty_t_pair(
            ( name = `CATALOG_NAME`             value = cube-catalog_name )
            ( name = `SCHEMA_NAME`              value = cube-catalog_name )
            ( name = `CUBE_NAME`                value = cube-cube_name )
            ( name = `DIMENSION_UNIQUE_NAME`    value = |[{ dim-dim_name }]| )
            ( name = `HIERARCHY_NAME`           value = hier_name )
            ( name = `HIERARCHY_UNIQUE_NAME`    value = unique_name )
            ( name = `HIERARCHY_CAPTION`        value = hier-caption )
            ( name = `DIMENSION_TYPE`           value = |{ dimension_type_code( dim-dim_type ) }| )
            ( name = `HIERARCHY_CARDINALITY`    value = |{ cardinality }| )
            ( name = `DEFAULT_MEMBER`           value = default_member( model ) ) ).
          IF hier-has_all = abap_true.
            APPEND VALUE #( name = `ALL_MEMBER` value = all_member ) TO columns.
          ENDIF.
          APPEND LINES OF VALUE ty_t_pair(
            ( name = `DESCRIPTION`              value = |{ cube-cube_name } Cube - { hier_name } Hierarchy| )
            ( name = `STRUCTURE`                value = `0` )
            ( name = `IS_VIRTUAL`               value = `false` )
            ( name = `IS_READWRITE`             value = `false` )
            ( name = `DIMENSION_UNIQUE_SETTINGS` value = `0` )
            ( name = `DIMENSION_IS_VISIBLE`     value = `true` )
            ( name = `HIERARCHY_ORDINAL`        value = |{ ordinal }| )
            ( name = `DIMENSION_IS_SHARED`      value = `true` )
            ( name = `HIERARCHY_IS_VISIBLE`     value = `true` )
            ( name = `HIERARCHY_ORIGIN`         value = |{ hier-origin }| )
            ( name = `HIERARCHY_DISPLAY_FOLDER` value = `` )
            ( name = `HIERARCHY_VISIBILITY`     value = `1` )
            ( name = `PARENT_CHILD`             value = `false` ) ) TO columns.
          APPEND VALUE #( name = hier_name xml = row_xml( columns ) ) TO lines.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.

    SORT lines BY name ASCENDING.
    LOOP AT lines INTO DATA(line).
      result = result && line-xml.
    ENDLOOP.
  ENDMETHOD.

  METHOD level_xml.
    result = row_xml( VALUE #(
      ( name = `CATALOG_NAME`           value = catalog )
      ( name = `SCHEMA_NAME`            value = catalog )
      ( name = `CUBE_NAME`              value = cube )
      ( name = `DIMENSION_UNIQUE_NAME`  value = dimension )
      ( name = `HIERARCHY_UNIQUE_NAME`  value = hierarchy_unique )
      ( name = `LEVEL_NAME`             value = level_name )
      ( name = `LEVEL_UNIQUE_NAME`      value = |{ hierarchy_unique }.[{ level_name }]| )
      ( name = `LEVEL_CAPTION`          value = level_name )
      ( name = `LEVEL_NUMBER`           value = |{ number }| )
      ( name = `LEVEL_CARDINALITY`      value = |{ cardinality }| )
      ( name = `LEVEL_TYPE`             value = |{ type }| )
      ( name = `CUSTOM_ROLLUP_SETTINGS` value = `0` )
      ( name = `LEVEL_UNIQUE_SETTINGS`  value = |{ unique_settings }| )
      ( name = `LEVEL_IS_VISIBLE`       value = `true` )
      ( name = `DESCRIPTION`            value = |{ cube } Cube - { hierarchy_name } Hierarchy - { level_name } Level| )
      ( name = `LEVEL_ORIGIN`           value = `0` ) ) ).
  ENDMETHOD.

  METHOD level_type_code.
    result = SWITCH #( level_type
                       WHEN `TimeYears`     THEN 20     " 0x0014
                       WHEN `TimeHalfYears` THEN 36     " 0x0024
                       WHEN `TimeQuarters`  THEN 68     " 0x0044
                       WHEN `TimeMonths`    THEN 132    " 0x0084
                       WHEN `TimeWeeks`     THEN 260    " 0x0104
                       WHEN `TimeDays`      THEN 516    " 0x0204
                       WHEN `TimeHours`     THEN 772    " 0x0304
                       WHEN `TimeMinutes`   THEN 1028   " 0x0404
                       WHEN `TimeSeconds`   THEN 2052   " 0x0804
                       WHEN `TimeUndefined` THEN 4100   " 0x1004
                       ELSE 0 ).
  ENDMETHOD.

  METHOD dimension_type_code.
    result = COND #( WHEN dim_type = `Time` THEN 1 ELSE 3 ).
  ENDMETHOD.

  METHOD mdschema_levels.
    " The levels of a cube as the reference lists them: the single level of Measures, and per hierarchy of the model the
    " (All) level (number 0, cardinality 1) and the levels of the model. Sorted by the unique name of the hierarchy,
    " then by level number. The cardinality is counted in the database (ZZXXMLA1_CL_MODEL=>LEVEL_CARDINALITY).
    TYPES: BEGIN OF ty_line,
             name TYPE string,
             xml  TYPE string,
           END OF ty_line.
    DATA lines TYPE STANDARD TABLE OF ty_line WITH EMPTY KEY.
    DATA(wanted_catalog) = VALUE string( request-properties[ name = 'Catalog' ]-value OPTIONAL ).

    DATA(cubes) = schema->cubes( ).
    LOOP AT cubes INTO DATA(cube).
      IF ( wanted_catalog IS NOT INITIAL AND cube-catalog_name <> wanted_catalog )
          OR is_allowed( request = request restriction = `CATALOG_NAME` value = cube-catalog_name ) = abap_false
          OR is_allowed( request = request restriction = `SCHEMA_NAME` value = cube-catalog_name ) = abap_false
          OR is_allowed( request = request restriction = `CUBE_NAME` value = cube-cube_name ) = abap_false.
        CONTINUE.
      ENDIF.

      DATA(measure_count) = lines( schema->measures( cube-cube_name ) ).
      IF is_allowed( request = request restriction = `DIMENSION_UNIQUE_NAME` value = `[Measures]` ) = abap_true
          AND is_allowed( request = request restriction = `HIERARCHY_UNIQUE_NAME` value = `[Measures]` ) = abap_true
          AND is_allowed( request = request restriction = `LEVEL_NAME` value = `MeasuresLevel` ) = abap_true
          AND is_allowed( request = request restriction = `LEVEL_UNIQUE_NAME` value = `[Measures].[MeasuresLevel]` ) = abap_true.
        APPEND VALUE #( name = `[Measures]`
                        xml  = level_xml( catalog = cube-catalog_name cube = cube-cube_name dimension = `[Measures]`
                                          hierarchy_name = `Measures` hierarchy_unique = `[Measures]`
                                          level_name = `MeasuresLevel` number = 0 cardinality = measure_count + 1
                                          type = 0 unique_settings = 0 ) ) TO lines.
      ENDIF.

      DATA(dims) = schema->dimensions( cube-cube_name ).
      LOOP AT dims INTO DATA(dim).
        DATA(hiers) = schema->hierarchies( cube = cube-cube_name dim = dim-dim_name ).
        LOOP AT hiers INTO DATA(hier).
          DATA(hier_name) = hier-name.
          DATA(unique_name) = hierarchy_unique_name( dim_name = dim-dim_name hier_name = hier-hier_name ).
          IF is_allowed( request = request restriction = `DIMENSION_UNIQUE_NAME` value = |[{ dim-dim_name }]| ) = abap_false
              OR is_allowed( request = request restriction = `HIERARCHY_UNIQUE_NAME` value = unique_name ) = abap_false.
            CONTINUE.
          ENDIF.

          IF hier-has_all = 'X'
              AND is_allowed( request = request restriction = `LEVEL_NAME` value = `(All)` ) = abap_true
              AND is_allowed( request = request restriction = `LEVEL_UNIQUE_NAME` value = |{ unique_name }.[(All)]| ) = abap_true.
            APPEND VALUE #( name = unique_name
                            xml  = level_xml( catalog = cube-catalog_name cube = cube-cube_name
                                              dimension = |[{ dim-dim_name }]| hierarchy_name = hier_name
                                              hierarchy_unique = unique_name level_name = `(All)`
                                              number = 0 cardinality = 1 type = 1 unique_settings = 3 ) ) TO lines.
          ENDIF.

          DATA(model) = model_hierarchy( cube = cube-cube_name dim = dim-dim_name hier = hier-hier_name ).
          LOOP AT model-levels INTO DATA(level).
            DATA(level_no) = sy-tabix.
            IF is_allowed( request = request restriction = `LEVEL_NAME` value = level-level_name ) = abap_false
                OR is_allowed( request = request restriction = `LEVEL_UNIQUE_NAME` value = |{ unique_name }.[{ level-level_name }]| ) = abap_false.
              CONTINUE.
            ENDIF.
            APPEND VALUE #( name = unique_name
                            xml  = level_xml(
                              catalog = cube-catalog_name cube = cube-cube_name dimension = |[{ dim-dim_name }]|
                              hierarchy_name = hier_name hierarchy_unique = unique_name level_name = level-level_name
                              number = COND #( WHEN hier-has_all = abap_true THEN level_no ELSE level_no - 1 )
                              cardinality = zzxxmla1_cl_model=>level_cardinality( hierarchy = model level_no = level_no )
                              type = level_type_code( level-level_type )
                              unique_settings = COND #( WHEN level-unique_members = 'X' THEN 1 ELSE 0 ) ) ) TO lines.
          ENDLOOP.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.

    SORT lines STABLE BY name ASCENDING.
    LOOP AT lines INTO DATA(line).
      result = result && line-xml.
    ENDLOOP.
  ENDMETHOD.

  METHOD hierarchy_members.
    " The reference lists a hierarchy level by level (MdschemaMembersRowset.populateHierarchy), each level in hierarchy order
    DATA(model) = model_hierarchy( cube = dim-cube_name dim = dim-dim_name hier = hier-hier_name ).
    DATA(unique) = model-unique_name.
    DATA(dimension) = |[{ dim-dim_name }]|.
    DATA(members) = zzxxmla1_cl_model=>members( model ).
    DATA(offset) = 0.
    DATA(all_member) = VALUE string( ).
    IF model-has_all = abap_true.
      offset = 1.
      all_member = |{ unique }.{ zzxxmla1_cl_model=>quote_name( model-all_member_name ) }|.
      APPEND VALUE #( dimension = dimension hierarchy = unique level = |{ unique }.[(All)]| number = 0
                      name = model-all_member_name unique = all_member type = 2
                      cardinality = REDUCE i( INIT n = 0 FOR m IN members WHERE ( level_no = 1 ) NEXT n = n + 1 ) )
             TO result.
    ENDIF.
    LOOP AT model-levels INTO DATA(level).
      DATA(level_no) = sy-tabix.
      DATA(depth) = level_no - 1 + offset.
      LOOP AT members INTO DATA(member) WHERE level_no = level_no.
        DATA(parent) = COND string( WHEN member-parent IS NOT INITIAL THEN member-parent ELSE all_member ).
        APPEND VALUE #( dimension = dimension hierarchy = unique level = |{ unique }.[{ level-level_name }]|
                        number = depth name = member-name unique = member-unique_name type = 1
                        cardinality = member-children parent = parent
                        parent_level = COND #( WHEN depth > 0 THEN depth - 1 )
                        parent_count = COND #( WHEN parent IS NOT INITIAL THEN 1 ) depth = depth )
               TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD model_hierarchy.
    LOOP AT zzxxmla1_cl_model=>hierarchies( cube ) INTO result WHERE dim_name = dim AND hier_name = hier.
      RETURN.
    ENDLOOP.
    CLEAR result.
  ENDMETHOD.

  METHOD default_member.
    IF hierarchy-default_member IS NOT INITIAL.
      result = hierarchy-default_member.
    ELSEIF hierarchy-has_all = abap_true.
      result = |{ hierarchy-unique_name }.{ zzxxmla1_cl_model=>quote_name( hierarchy-all_member_name ) }|.
    ELSE.
      DATA(members) = zzxxmla1_cl_model=>members( hierarchy ).
      result = VALUE #( members[ 1 ]-unique_name OPTIONAL ).
    ENDIF.
  ENDMETHOD.

  METHOD measure_members.
    DATA(measures) = schema->measures( cube ).
    LOOP AT measures INTO DATA(measure).
      APPEND VALUE #( dimension = `[Measures]` hierarchy = `[Measures]` level = `[Measures].[MeasuresLevel]` number = 0
                      name = measure-meas_name unique = |[Measures].[{ measure-meas_name }]| type = 3 )
             TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD select_members.
    " The reference gives no rows when the member type is restricted (observed), and ignores MEMBER_CAPTION
    IF line_exists( request-restrictions[ name = 'MEMBER_TYPE' ] ).
      RETURN.
    ENDIF.

    DATA candidates TYPE ty_t_member.
    IF line_exists( request-restrictions[ name = 'TREE_OP' ] ) AND line_exists( request-restrictions[ name = 'MEMBER_UNIQUE_NAME' ] ).
      DATA(anchor_name) = request-restrictions[ name = 'MEMBER_UNIQUE_NAME' ]-value.
      READ TABLE members INTO DATA(anchor) WITH KEY unique = anchor_name.
      IF sy-subrc <> 0.
        RETURN.
      ENDIF.
      populate_member( EXPORTING members = members member = anchor
                                 tree_op = CONV i( request-restrictions[ name = 'TREE_OP' ]-value )
                       CHANGING  result  = candidates ).
    ELSE.
      LOOP AT members INTO DATA(member).
        IF is_allowed( request = request restriction = `MEMBER_UNIQUE_NAME` value = member-unique ) = abap_true.
          APPEND member TO candidates.
        ENDIF.
      ENDLOOP.
    ENDIF.

    LOOP AT candidates INTO DATA(candidate).
      IF is_allowed( request = request restriction = `LEVEL_UNIQUE_NAME` value = candidate-level ) = abap_true
          AND is_allowed( request = request restriction = `LEVEL_NUMBER` value = |{ candidate-number }| ) = abap_true
          AND is_allowed( request = request restriction = `MEMBER_NAME` value = candidate-name ) = abap_true.
        APPEND candidate TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD populate_member.
    " TREE_OP: 1 children, 2 siblings, 4 parent, 8 self, 16 descendants, 32 ancestors
    IF tree_op DIV 8 MOD 2 = 1.
      APPEND member TO result.
    ENDIF.
    IF tree_op DIV 2 MOD 2 = 1.
      " the siblings: the other children of the parent, or the other root members
      LOOP AT members INTO DATA(sibling) WHERE parent = member-parent AND unique <> member-unique.
        populate_member( EXPORTING members = members member = sibling tree_op = 8 CHANGING result = result ).
      ENDLOOP.
    ENDIF.
    " descendants or children, not both
    IF tree_op DIV 16 MOD 2 = 1 OR tree_op MOD 2 = 1.
      DATA(child_op) = COND i( WHEN tree_op DIV 16 MOD 2 = 1 THEN 8 + 16 ELSE 8 ).
      LOOP AT members INTO DATA(child) WHERE parent = member-unique.
        populate_member( EXPORTING members = members member = child tree_op = child_op CHANGING result = result ).
      ENDLOOP.
    ENDIF.
    " ancestors or parent, not both
    IF member-parent IS NOT INITIAL AND ( tree_op DIV 32 MOD 2 = 1 OR tree_op DIV 4 MOD 2 = 1 ).
      READ TABLE members INTO DATA(parent) WITH KEY unique = member-parent.
      IF sy-subrc = 0.
        populate_member( EXPORTING members = members member = parent
                                   tree_op = COND #( WHEN tree_op DIV 32 MOD 2 = 1 THEN 8 + 32 ELSE 8 )
                         CHANGING  result  = result ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD mdschema_members.
    " MDSCHEMA_MEMBERS: all members of all hierarchies of the cubes of the model, restricted as asked, sorted as
    " The reference sorts the rowset (stable, by dimension, hierarchy, level unique name and level number). Hierarchies are
    " chosen first and only the chosen ones are read from the database.
    TYPES: BEGIN OF ty_hierarchy,
             unique    TYPE string,
             dimension TYPE string,
             cube      TYPE zzxxmla1_cl_schema=>ty_cube,
             dim       TYPE zzxxmla1_cl_schema=>ty_dim,
             hier      TYPE zzxxmla1_cl_schema=>ty_hier,
           END OF ty_hierarchy.
    DATA hierarchies TYPE STANDARD TABLE OF ty_hierarchy WITH EMPTY KEY.
    DATA parts TYPE string_table.
    DATA(wanted_catalog) = VALUE string( request-properties[ name = 'Catalog' ]-value OPTIONAL ).

    " the hierarchy a member or level unique name belongs to: its text up to the first closing bracket of the name
    DATA(derived) = VALUE string( ).
    LOOP AT request-restrictions INTO DATA(restriction) WHERE name = 'MEMBER_UNIQUE_NAME' OR name = 'LEVEL_UNIQUE_NAME'.
      DATA(position) = find( val = restriction-value sub = `].[` ).
      IF position > 0.
        derived = substring( val = restriction-value len = position + 1 ).
      ENDIF.
    ENDLOOP.

    DATA(cubes) = schema->cubes( ).
    LOOP AT cubes INTO DATA(cube).
      IF ( wanted_catalog IS NOT INITIAL AND cube-catalog_name <> wanted_catalog )
          OR is_allowed( request = request restriction = `CATALOG_NAME` value = cube-catalog_name ) = abap_false
          OR is_allowed( request = request restriction = `SCHEMA_NAME` value = cube-catalog_name ) = abap_false
          OR is_allowed( request = request restriction = `CUBE_NAME` value = cube-cube_name ) = abap_false.
        CONTINUE.
      ENDIF.

      hierarchies = VALUE #( ).
      IF is_allowed( request = request restriction = `DIMENSION_UNIQUE_NAME` value = `[Measures]` ) = abap_true
          AND is_allowed( request = request restriction = `HIERARCHY_UNIQUE_NAME` value = `[Measures]` ) = abap_true
          AND ( derived IS INITIAL OR derived = `[Measures]` ).
        APPEND VALUE #( unique = `[Measures]` dimension = `[Measures]` cube = cube ) TO hierarchies.
      ENDIF.
      DATA(dims) = schema->dimensions( cube-cube_name ).
      LOOP AT dims INTO DATA(dim).
        DATA(hiers) = schema->hierarchies( cube = cube-cube_name dim = dim-dim_name ).
        LOOP AT hiers INTO DATA(hier).
          DATA(unique_name) = hierarchy_unique_name( dim_name = dim-dim_name hier_name = hier-hier_name ).
          IF is_allowed( request = request restriction = `DIMENSION_UNIQUE_NAME` value = |[{ dim-dim_name }]| ) = abap_true
              AND is_allowed( request = request restriction = `HIERARCHY_UNIQUE_NAME` value = unique_name ) = abap_true
              AND ( derived IS INITIAL OR derived = unique_name ).
            APPEND VALUE #( unique = unique_name dimension = |[{ dim-dim_name }]| cube = cube dim = dim hier = hier )
                   TO hierarchies.
          ENDIF.
        ENDLOOP.
      ENDLOOP.
      SORT hierarchies BY unique ASCENDING.

      DATA(rows) = VALUE ty_t_member( ).
      LOOP AT hierarchies INTO DATA(hierarchy).
        DATA(members) = COND ty_t_member(
          WHEN hierarchy-unique = `[Measures]` THEN measure_members( cube-cube_name )
          ELSE hierarchy_members( dim = hierarchy-dim hier = hierarchy-hier ) ).
        APPEND LINES OF select_members( request = request members = members ) TO rows.
      ENDLOOP.
      SORT rows STABLE BY dimension ASCENDING hierarchy ASCENDING level ASCENDING number ASCENDING.
      LOOP AT rows INTO DATA(member).
        DATA(columns) = VALUE ty_t_pair(
          ( name = `CATALOG_NAME`          value = cube-catalog_name )
          ( name = `SCHEMA_NAME`           value = cube-catalog_name )
          ( name = `CUBE_NAME`             value = cube-cube_name )
          ( name = `DIMENSION_UNIQUE_NAME` value = member-dimension )
          ( name = `HIERARCHY_UNIQUE_NAME` value = member-hierarchy )
          ( name = `LEVEL_UNIQUE_NAME`     value = member-level )
          ( name = `LEVEL_NUMBER`          value = |{ member-number }| )
          ( name = `MEMBER_ORDINAL`        value = `0` )
          ( name = `MEMBER_NAME`           value = member-name )
          ( name = `MEMBER_UNIQUE_NAME`    value = member-unique )
          ( name = `MEMBER_TYPE`           value = |{ member-type }| )
          ( name = `MEMBER_CAPTION`        value = member-name )
          ( name = `CHILDREN_CARDINALITY`  value = |{ member-cardinality }| )
          ( name = `PARENT_LEVEL`          value = |{ member-parent_level }| ) ).
        IF member-parent IS NOT INITIAL.
          APPEND VALUE #( name = `PARENT_UNIQUE_NAME` value = member-parent ) TO columns.
        ENDIF.
        APPEND VALUE #( name = `PARENT_COUNT` value = |{ member-parent_count }| ) TO columns.
        APPEND VALUE #( name = `DEPTH` value = |{ member-depth }| ) TO columns.
        APPEND row_xml( columns ) TO parts.
      ENDLOOP.
    ENDLOOP.
    result = concat_lines_of( table = parts ).
  ENDMETHOD.

  METHOD selected_cubes.
    DATA(wanted_catalog) = VALUE string( request-properties[ name = 'Catalog' ]-value OPTIONAL ).
    DATA(cubes) = schema->cubes( ).
    LOOP AT cubes INTO DATA(cube).
      IF ( wanted_catalog IS NOT INITIAL AND cube-catalog_name <> wanted_catalog )
          OR is_allowed( request = request restriction = catalog_column value = cube-catalog_name ) = abap_false
          OR is_allowed( request = request restriction = cube_column value = cube-cube_name ) = abap_false.
        CONTINUE.
      ENDIF.
      APPEND cube TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD static_rowset.
    " The rows are the same for every cube. Which restrictions the reference applies (checked against the reference server): only
    " FUNCTION_NAME (exact, case sensitive) for the functions; none for enumerators, keywords and literals; for the
    " provider types a DATA_TYPE restriction of any value gives no rows and BEST_MATCH is ignored.
    DATA parts TYPE string_table.
    IF request-type = 'DBSCHEMA_PROVIDER_TYPES' AND line_exists( request-restrictions[ name = 'DATA_TYPE' ] ).
      RETURN.
    ENDIF.
    LOOP AT zzxxmla1_cl_xmla_static=>get_rows( request-type ) INTO DATA(row).
      IF request-type = 'MDSCHEMA_FUNCTIONS'
          AND is_allowed( request = request restriction = `FUNCTION_NAME` value = VALUE string( row[ name = 'FUNCTION_NAME' ]-value OPTIONAL ) ) = abap_false.
        CONTINUE.
      ENDIF.
      APPEND row_xml( row ) TO parts.
    ENDLOOP.
    result = concat_lines_of( table = parts ).
  ENDMETHOD.

  METHOD dbschema_schemata.
    " one schema per catalog, named like it
    LOOP AT catalogs( ) INTO DATA(catalog).
      IF is_allowed( request = request restriction = `CATALOG_NAME` value = catalog ) = abap_false
          OR is_allowed( request = request restriction = `SCHEMA_NAME` value = catalog ) = abap_false
          OR is_allowed( request = request restriction = `SCHEMA_OWNER` value = `` ) = abap_false.
        CONTINUE.
      ENDIF.
      result = result && row_xml( VALUE #(
        ( name = `CATALOG_NAME` value = catalog )
        ( name = `SCHEMA_NAME`  value = catalog )
        ( name = `SCHEMA_OWNER` value = `` ) ) ).
    ENDLOOP.
  ENDMETHOD.

  METHOD dbschema_tables_info.
    " one table per cube; the reference reports the same cardinality for every cube
    LOOP AT selected_cubes( request = request catalog_column = `TABLE_CATALOG` cube_column = `TABLE_NAME` ) INTO DATA(cube).
      IF is_allowed( request = request restriction = `TABLE_TYPE` value = `TABLE` ) = abap_false.
        CONTINUE.
      ENDIF.
      result = result && row_xml( VALUE #(
        ( name = `TABLE_CATALOG`  value = cube-catalog_name )
        ( name = `TABLE_NAME`     value = cube-cube_name )
        ( name = `TABLE_TYPE`     value = `TABLE` )
        ( name = `BOOKMARKS`      value = `false` )
        ( name = `TABLE_VERSION`  value = `null` )
        ( name = `CARDINALITY`    value = `1000000` )
        ( name = `DESCRIPTION`    value = |{ cube-catalog_name } - { cube-cube_name } Cube| ) ) ).
    ENDLOOP.
  ENDMETHOD.

  METHOD mdschema_measuregroups.
    " The reference has one measure group per cube, named like the cube
    LOOP AT selected_cubes( request ) INTO DATA(cube).
      IF is_allowed( request = request restriction = `SCHEMA_NAME` value = cube-catalog_name ) = abap_false
          OR is_allowed( request = request restriction = `MEASUREGROUP_NAME` value = cube-cube_name ) = abap_false.
        CONTINUE.
      ENDIF.
      result = result && row_xml( VALUE #(
        ( name = `CATALOG_NAME`         value = cube-catalog_name )
        ( name = `SCHEMA_NAME`          value = cube-catalog_name )
        ( name = `CUBE_NAME`            value = cube-cube_name )
        ( name = `MEASUREGROUP_NAME`    value = cube-cube_name )
        ( name = `DESCRIPTION`          value = `` )
        ( name = `IS_WRITE_ENABLED`     value = `false` )
        ( name = `MEASUREGROUP_CAPTION` value = cube-cube_name ) ) ).
    ENDLOOP.
  ENDMETHOD.

  METHOD measuregroup_dimensions.
    " every dimension of the cube, also Measures, is related to the one measure group; sorted by dimension name
    LOOP AT selected_cubes( request ) INTO DATA(cube).
      IF is_allowed( request = request restriction = `SCHEMA_NAME` value = cube-catalog_name ) = abap_false
          OR is_allowed( request = request restriction = `MEASUREGROUP_NAME` value = cube-cube_name ) = abap_false.
        CONTINUE.
      ENDIF.
      DATA(dims) = schema->dimensions( cube-cube_name ).
      DATA(names) = VALUE string_table( ( `Measures` ) ).
      LOOP AT dims INTO DATA(dim).
        APPEND CONV string( dim-dim_name ) TO names.
      ENDLOOP.
      SORT names ASCENDING.
      LOOP AT names INTO DATA(name).
        IF is_allowed( request = request restriction = `DIMENSION_UNIQUE_NAME` value = |[{ name }]| ) = abap_false.
          CONTINUE.
        ENDIF.
        result = result && row_xml( VALUE #(
          ( name = `CATALOG_NAME`              value = cube-catalog_name )
          ( name = `SCHEMA_NAME`               value = cube-catalog_name )
          ( name = `CUBE_NAME`                 value = cube-cube_name )
          ( name = `MEASUREGROUP_NAME`         value = cube-cube_name )
          ( name = `MEASUREGROUP_CARDINALITY`  value = `ONE` )
          ( name = `DIMENSION_UNIQUE_NAME`     value = |[{ name }]| )
          ( name = `DIMENSION_CARDINALITY`     value = `MANY` )
          ( name = `DIMENSION_IS_VISIBLE`      value = `true` )
          ( name = `DIMENSION_IS_FACT_DIMENSION` value = `0` )
          ( name = `DIMENSION_PATH`            value = `` )
          ( name = `DIMENSION_GRANULARITY`     value = `` ) ) ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD levels_of.
    IF hier-has_all = 'X'.
      APPEND `(All)` TO result.
    ENDIF.
    DATA(levels) = schema->levels( cube = dim-cube_name dim = dim-dim_name hier = hier-hier_name ).
    LOOP AT levels INTO DATA(level).
      APPEND CONV string( level-level_name ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD level_columns.
    " the properties of a member that the reference lists as columns, with their OLE DB type: 130 text, 5 number, 11 flag
    DATA(standard) =
      `NAME:130 UNIQUE_NAME:130 CATALOG_NAME:130 SCHEMA_NAME:130 CUBE_NAME:130 DIMENSION_UNIQUE_NAME:130 ` &&
      `HIERARCHY_UNIQUE_NAME:130 LEVEL_UNIQUE_NAME:130 LEVEL_NUMBER:5 MEMBER_ORDINAL:5 MEMBER_NAME:130 ` &&
      `MEMBER_UNIQUE_NAME:130 MEMBER_TYPE:130 MEMBER_GUID:130 MEMBER_CAPTION:130 CHILDREN_CARDINALITY:5 ` &&
      `PARENT_LEVEL:5 PARENT_UNIQUE_NAME:130 PARENT_COUNT:5 DESCRIPTION:130 $visible:11 MEMBER_KEY:130 ` &&
      `IS_PLACEHOLDERMEMBER:11 IS_DATAMEMBER:11 DEPTH:5 DISPLAY_INFO:5 VALUE:130 $scenario:130 CELL_FORMATTER:130 ` &&
      `CELL_FORMATTER_SCRIPT:130 CELL_FORMATTER_SCRIPT_LANGUAGE:130 DISPLAY_FOLDER:130 FORMAT_EXP:130 KEY:130`.
    IF all_level = abap_true.
      APPEND VALUE #( name = |{ prefix }!NAME| value = `130` ) TO result.
      APPEND VALUE #( name = |{ prefix }!UNIQUE_NAME| value = `130` ) TO result.
    ENDIF.
    SPLIT standard AT ` ` INTO TABLE DATA(items).
    LOOP AT items INTO DATA(item).
      SPLIT item AT `:` INTO DATA(name) DATA(type).
      APPEND VALUE #( name = |{ prefix }!{ name }| value = type ) TO result.
    ENDLOOP.
    IF has_name = abap_true.
      APPEND VALUE #( name = |{ prefix }!$name| value = `130` ) TO result.
    ENDIF.
    " the level's member properties follow (getDBTypeFromProperty)
    LOOP AT properties INTO DATA(property).
      APPEND VALUE #( name  = |{ prefix }!{ property-name }|
                      value = SWITCH #( property-data_type WHEN `Numeric` OR `Integer` THEN `5`
                                                           WHEN `Boolean` THEN `11`
                                                           ELSE `130` ) ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD dbschema_tables.
    " The reference shows every level of every hierarchy as a system table "cube:Dimension.Hierarchy:Level" (sorted by
    " name; Measures is not among them), then the cube as a table
    TYPES: BEGIN OF ty_line,
             name TYPE string,
             xml  TYPE string,
           END OF ty_line.
    LOOP AT selected_cubes( request = request catalog_column = `TABLE_CATALOG` cube_column = `` ) INTO DATA(cube).
      DATA lines TYPE STANDARD TABLE OF ty_line WITH EMPTY KEY.
      CLEAR lines.
      DATA(dims) = schema->dimensions( cube-cube_name ).
      LOOP AT dims INTO DATA(dim).
        DATA(hiers) = schema->hierarchies( cube = cube-cube_name dim = dim-dim_name ).
        LOOP AT hiers INTO DATA(hier).
          DATA(hier_name) = hier-name.
          LOOP AT levels_of( dim = dim hier = hier ) INTO DATA(level).
            DATA(table_name) = |{ cube-cube_name }:{ hier_name }:{ level }|.
            IF is_allowed( request = request restriction = `TABLE_NAME` value = table_name ) = abap_true
                AND is_allowed( request = request restriction = `TABLE_TYPE` value = `SYSTEM TABLE` ) = abap_true.
              APPEND VALUE #( name = table_name
                              xml  = row_xml( VALUE #(
                ( name = `TABLE_CATALOG` value = cube-catalog_name )
                ( name = `TABLE_NAME`    value = table_name )
                ( name = `TABLE_TYPE`    value = `SYSTEM TABLE` )
                ( name = `DESCRIPTION`   value = |{ cube-catalog_name } - { cube-cube_name } Cube - { hier_name } Hierarchy - { level } Level| ) ) ) )
                     TO lines.
            ENDIF.
          ENDLOOP.
        ENDLOOP.
      ENDLOOP.
      SORT lines BY name ASCENDING.
      LOOP AT lines INTO DATA(line).
        result = result && line-xml.
      ENDLOOP.
      IF is_allowed( request = request restriction = `TABLE_NAME` value = cube-cube_name ) = abap_true
          AND is_allowed( request = request restriction = `TABLE_TYPE` value = `TABLE` ) = abap_true.
        result = result && row_xml( VALUE #(
          ( name = `TABLE_CATALOG` value = cube-catalog_name )
          ( name = `TABLE_NAME`    value = cube-cube_name )
          ( name = `TABLE_TYPE`    value = `TABLE` )
          ( name = `DESCRIPTION`   value = |{ cube-catalog_name } - { cube-cube_name } Cube| ) ) ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD dbschema_columns.
    " The cube as a flat table: the member properties of every level (Measures first, then the hierarchies in model
    " order, each with its (All) level), then the measures except the default one. Numbered over the whole cube.
    DATA parts TYPE string_table.
    LOOP AT selected_cubes( request = request catalog_column = `TABLE_CATALOG` cube_column = `TABLE_NAME` ) INTO DATA(cube).
      DATA columns TYPE ty_t_pair.
      columns = level_columns( prefix = `Measures:MeasuresLevel` all_level = abap_false ).
      DATA(dims) = schema->dimensions( cube-cube_name ).
      LOOP AT dims INTO DATA(dim).
        DATA(hiers) = schema->hierarchies( cube = cube-cube_name dim = dim-dim_name ).
        LOOP AT hiers INTO DATA(hier).
          DATA(levels) = schema->levels( cube = cube-cube_name dim = dim-dim_name hier = hier-hier_name ).
          LOOP AT levels_of( dim = dim hier = hier ) INTO DATA(level).
            DATA(definition) = VALUE zzxxmla1_cl_schema=>ty_level( levels[ level_name = level ] OPTIONAL ).
            APPEND LINES OF level_columns( prefix    = |{ hier-name }:{ level }|
                                           all_level = xsdbool( level = `(All)` )
                                           has_name  = xsdbool( definition-name_column <> definition-key_column )
                                           properties = definition-properties )
                   TO columns.
          ENDLOOP.
        ENDLOOP.
      ENDLOOP.
      DATA(measures) = schema->measures( cube-cube_name ).
      LOOP AT measures INTO DATA(measure) FROM 2.
        APPEND VALUE #( name = |Measures:{ measure-meas_name }| value = `5` ) TO columns.
      ENDLOOP.

      LOOP AT columns INTO DATA(column).
        DATA(position) = sy-tabix.
        IF is_allowed( request = request restriction = `COLUMN_NAME` value = column-name ) = abap_false.
          CONTINUE.
        ENDIF.
        DATA(row) = VALUE ty_t_pair(
          ( name = `TABLE_CATALOG`      value = cube-catalog_name )
          ( name = `TABLE_NAME`         value = cube-cube_name )
          ( name = `COLUMN_NAME`        value = column-name )
          ( name = `ORDINAL_POSITION`   value = |{ position }| )
          ( name = `COLUMN_HAS_DEFAULT` value = `false` )
          ( name = `COLUMN_FLAGS`       value = `0` )
          ( name = `IS_NULLABLE`        value = `false` )
          ( name = `DATA_TYPE`          value = column-value ) ).
        CASE column-value.
          WHEN `130`.
            APPEND VALUE #( name = `CHARACTER_MAXIMUM_LENGTH` value = `0` ) TO row.
            APPEND VALUE #( name = `CHARACTER_OCTET_LENGTH`   value = `0` ) TO row.
          WHEN `5`.
            APPEND VALUE #( name = `NUMERIC_PRECISION` value = `16` ) TO row.
            APPEND VALUE #( name = `NUMERIC_SCALE`     value = `255` ) TO row.
          WHEN OTHERS.
            APPEND VALUE #( name = `NUMERIC_PRECISION` value = `255` ) TO row.
            APPEND VALUE #( name = `NUMERIC_SCALE`     value = `255` ) TO row.
        ENDCASE.
        APPEND row_xml( row ) TO parts.
      ENDLOOP.
    ENDLOOP.
    result = concat_lines_of( table = parts ).
  ENDMETHOD.

  METHOD is_allowed.
    result = abap_true.
    IF line_exists( request-restrictions[ name = restriction ] ).
      result = xsdbool( line_exists( request-restrictions[ name = restriction value = value ] ) ).
    ENDIF.
  ENDMETHOD.

  METHOD mdschema_properties.
    DATA(mask) = 1.
    IF line_exists( request-restrictions[ name = `PROPERTY_TYPE` ] ).
      TRY.
          mask = request-restrictions[ name = `PROPERTY_TYPE` ]-value.
        CATCH cx_sy_conversion_no_number.
          mask = 0.
      ENDTRY.
    ENDIF.
    IF mask MOD 2 = 1.
      result = member_properties( request ).
    ENDIF.
    IF mask MOD 4 < 2.
      " no cell properties asked for
      RETURN.
    ENDIF.
    " name and OLE DB type (DATA_TYPE) of each, in olap4j's order
    DATA(cell_properties) = VALUE ty_t_pair(
      ( name = `BACK_COLOR` value = `130` ) ( name = `CELL_EVALUATION_LIST` value = `130` )
      ( name = `CELL_ORDINAL` value = `19` ) ( name = `FORE_COLOR` value = `130` ) ( name = `FONT_NAME` value = `130` )
      ( name = `FONT_SIZE` value = `130` ) ( name = `FONT_FLAGS` value = `19` ) ( name = `FORMATTED_VALUE` value = `130` )
      ( name = `FORMAT_STRING` value = `130` ) ( name = `NON_EMPTY_BEHAVIOR` value = `130` )
      ( name = `SOLVE_ORDER` value = `3` ) ( name = `VALUE` value = `12` ) ( name = `DATATYPE` value = `130` )
      ( name = `LANGUAGE` value = `19` ) ( name = `ACTION_TYPE` value = `1009` ) ( name = `UPDATEABLE` value = `19` ) ).
    LOOP AT cell_properties INTO DATA(property).
      result = result && row_xml( VALUE #( ( name = `PROPERTY_TYPE` value = `2` )
                                           ( name = `PROPERTY_NAME` value = property-name )
                                           ( name = `PROPERTY_CAPTION` value = property-name )
                                           ( name = `DATA_TYPE` value = property-value ) ) ).
    ENDLOOP.
  ENDMETHOD.

  METHOD member_properties.
    DATA(wanted_catalog) = VALUE string( request-properties[ name = 'Catalog' ]-value OPTIONAL ).
    DATA(level_restricted) = xsdbool( line_exists( request-restrictions[ name = `LEVEL_UNIQUE_NAME` ] ) ).
    LOOP AT schema->cubes( ) INTO DATA(cube).
      IF ( wanted_catalog IS NOT INITIAL AND cube-catalog_name <> wanted_catalog )
          OR is_allowed( request = request restriction = `CATALOG_NAME` value = cube-catalog_name ) = abap_false
          OR is_allowed( request = request restriction = `SCHEMA_NAME` value = cube-catalog_name ) = abap_false
          OR is_allowed( request = request restriction = `CUBE_NAME` value = cube-cube_name ) = abap_false.
        CONTINUE.
      ENDIF.
      LOOP AT schema->dimensions( cube-cube_name ) INTO DATA(dim).
        DATA(dimension_unique) = |[{ dim-dim_name }]|.
        LOOP AT schema->hierarchies( cube = cube-cube_name dim = dim-dim_name ) INTO DATA(hier).
          DATA(hierarchy_unique) = hierarchy_unique_name( dim_name = dim-dim_name hier_name = hier-hier_name ).
          IF level_restricted = abap_false
              AND ( is_allowed( request = request restriction = `DIMENSION_UNIQUE_NAME` value = dimension_unique )
                      = abap_false
                    OR is_allowed( request = request restriction = `HIERARCHY_UNIQUE_NAME` value = hierarchy_unique )
                      = abap_false ).
            CONTINUE.
          ENDIF.
          LOOP AT schema->levels( cube = cube-cube_name dim = dim-dim_name hier = hier-hier_name ) INTO DATA(level).
            DATA(level_unique) = |{ hierarchy_unique }.[{ level-level_name }]|.
            IF is_allowed( request = request restriction = `LEVEL_UNIQUE_NAME` value = level_unique ) = abap_false.
              CONTINUE.
            ENDIF.
            LOOP AT level-properties INTO DATA(property).
              IF is_allowed( request = request restriction = `PROPERTY_NAME` value = property-name ) = abap_false.
                CONTINUE.
              ENDIF.
              " getDBTypeFromProperty: WSTR, R8 for the numbers, BOOL; a long is WSTR
              result = result && row_xml( VALUE #(
                ( name = `CATALOG_NAME` value = cube-catalog_name )
                ( name = `SCHEMA_NAME` value = cube-catalog_name )
                ( name = `CUBE_NAME` value = cube-cube_name )
                ( name = `DIMENSION_UNIQUE_NAME` value = dimension_unique )
                ( name = `HIERARCHY_UNIQUE_NAME` value = hierarchy_unique )
                ( name = `LEVEL_UNIQUE_NAME` value = level_unique )
                ( name = `PROPERTY_TYPE` value = `1` )
                ( name = `PROPERTY_NAME` value = property-name )
                ( name = `PROPERTY_CAPTION` value = property-caption )
                ( name = `DATA_TYPE` value = SWITCH #( property-data_type WHEN `Numeric` OR `Integer` THEN `5`
                                                                          WHEN `Boolean` THEN `11`
                                                                          ELSE `130` ) )
                ( name = `PROPERTY_CONTENT_TYPE` value = `0` )
                ( name = `DESCRIPTION` value = |{ cube-cube_name } Cube - { hier-name } Hierarchy - | &&
                                               |{ level-level_name } Level - { property-name } Property| )
                ( name = `CUBE_SOURCE` value = `2` )
                ( name = `PROPERTY_VISIBILITY` value = `1` ) ) ).
            ENDLOOP.
          ENDLOOP.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD row_xml.
    result = `      <row>` && cl_abap_char_utilities=>newline.
    LOOP AT columns INTO DATA(column).
      result = result && `        <` && column-name && `>` && xml_text( column-value ) && `</` && column-name && `>` &&
               cl_abap_char_utilities=>newline.
    ENDLOOP.
    result = result && `      </row>` && cl_abap_char_utilities=>newline.
  ENDMETHOD.

  METHOD timestamp_xml.
    " whole seconds: an ISO timestamp of a TIMESTAMPL has a decimal comma and seven digits, not an xsd:dateTime
    DATA seconds TYPE timestamp.
    seconds = trunc( timestamp ).
    result = |{ seconds TIMESTAMP = ISO }|.
  ENDMETHOD.

  METHOD discover_datasources.
    " the data sources of datasources.xml (FileRepository.getDatabases), the connect string without the database's
    " logon (Olap4jExtra.getDataSources); a data source without URL has this endpoint's
    LOOP AT repository->data_sources( ) INTO DATA(source).
      result = result && row_xml( VALUE #(
        ( name = `DataSourceName`        value = source-name )
        ( name = `DataSourceDescription` value = source-description )
        ( name = `URL`                   value = COND #( WHEN source-url IS NOT INITIAL THEN source-url ELSE url ) )
        ( name = `DataSourceInfo`        value = zzxxmla1_cl_repository=>public_data_source_info(
                                                   source-data_source_info ) )
        ( name = `ProviderName`          value = source-provider_name )
        ( name = `ProviderType`          value = `MDP` )
        ( name = `AuthenticationMode`    value = source-authentication_mode ) ) ).
    ENDLOOP.
  ENDMETHOD.

  METHOD discover_response.
    DATA(content) = VALUE string( request-properties[ name = 'Content' ]-value OPTIONAL ).
    IF content IS INITIAL.
      content = `SchemaData`.
    ENDIF.
    result =
      `<?xml version="1.0" encoding="UTF-8"?>` && cl_abap_char_utilities=>newline &&
      `<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">` && cl_abap_char_utilities=>newline &&
      `<SOAP-ENV:Header>` && cl_abap_char_utilities=>newline &&
      `</SOAP-ENV:Header>` && cl_abap_char_utilities=>newline &&
      `<SOAP-ENV:Body>` && cl_abap_char_utilities=>newline &&
      `<DiscoverResponse xmlns="` && c_ns_xmla && `">` && cl_abap_char_utilities=>newline &&
      `  <return>` && cl_abap_char_utilities=>newline &&
      `    <root xmlns="` && c_ns_xmla && `:rowset" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:EX="` && c_ns_xmla && `:exception">` && cl_abap_char_utilities=>newline &&
      COND string( WHEN content = `Schema` OR content = `SchemaData` THEN zzxxmla1_cl_xmla_rowsets=>xml_schema( request-type ) ) &&
      COND string( WHEN content = `Data` OR content = `SchemaData` THEN rows ) &&
      `    </root>` && cl_abap_char_utilities=>newline &&
      `  </return>` && cl_abap_char_utilities=>newline &&
      `</DiscoverResponse>` && cl_abap_char_utilities=>newline &&
      `</SOAP-ENV:Body>` && cl_abap_char_utilities=>newline &&
      `</SOAP-ENV:Envelope>` && cl_abap_char_utilities=>newline.
  ENDMETHOD.

  METHOD empty_execute_response.
    result =
      `<?xml version="1.0" encoding="UTF-8"?>` && cl_abap_char_utilities=>newline &&
      `<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">` && cl_abap_char_utilities=>newline &&
      `<SOAP-ENV:Header>` && cl_abap_char_utilities=>newline &&
      `</SOAP-ENV:Header>` && cl_abap_char_utilities=>newline &&
      `<SOAP-ENV:Body>` && cl_abap_char_utilities=>newline &&
      `<ExecuteResponse xmlns="` && c_ns_xmla && `">` && cl_abap_char_utilities=>newline &&
      `  <return>` && cl_abap_char_utilities=>newline &&
      `    <root xmlns="` && c_ns_xmla && `:empty" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:EX="` && c_ns_xmla && `:exception"/>` && cl_abap_char_utilities=>newline &&
      `  </return>` && cl_abap_char_utilities=>newline &&
      `</ExecuteResponse>` && cl_abap_char_utilities=>newline &&
      `</SOAP-ENV:Body>` && cl_abap_char_utilities=>newline &&
      `</SOAP-ENV:Envelope>` && cl_abap_char_utilities=>newline.
  ENDMETHOD.

  METHOD xml_text.
    result = escape( val = value format = cl_abap_format=>e_xml_text ).
  ENDMETHOD.

ENDCLASS.
