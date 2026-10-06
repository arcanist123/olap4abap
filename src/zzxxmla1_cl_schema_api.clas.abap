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
"! The API of the schema generator under /zzxxmla1/schema/api/ (docs/schema-generator.md, UI): strings in, strings out,
"! like ZZXXMLA1_CL_XMLA_HANDLER, so it is called from tests and from ZZXXMLA1_MAIN_ENDPOINT alike. Answers are JSON;
"! a refused request is {"error": "..."} with a 4xx or 5xx status.
"! - GET providers: the InfoCubes and cube-type aDSOs (ZZXXMLA1_CL_BW_PROVIDER);
"! - GET proposal?provider=X: the proposed schema (ZZXXMLA1_CL_SCHEMA_PROPOSAL) as XML and as an outline for the UI,
"!   with the notes and the time suggestions;
"! - GET schemas: the catalogs of /WEB-INF/datasources.xml, each name once (its first definition, as the XMLA endpoint
"!   reads them), with their schema files;
"! - GET schema?catalog=X: the catalog's schema as XML and as an outline, to edit an accepted schema again;
"! - POST check?catalog=X: the body is the edited schema XML. The checks of accept, nothing is changed: the schema
"!   parses, and the server's catalogs with this one load in ZZXXMLA1_CL_SCHEMA as the XMLA endpoint will load them.
"!   The schema file of an existing catalog is its Definition (it is replaced), of a new one
"!   /WEB-INF/schema/<catalog>.xml. Answers the file, whether the catalog is new and the characteristics whose views
"!   accept generates;
"! - POST accept?catalog=X: the checks of check, then the views of the tables named by their DDL source
"!   (ZZXXMLA1_C_<characteristic>) are generated (ZZXXMLA1_CL_BW_VIEW_GEN) and replaced by their database views,
"!   the schema file is written, a new catalog added to the first data source of /WEB-INF/datasources.xml, and the
"!   work is committed. Without catalog the schema's name is the catalog;
"! - POST remove?catalog=X: the catalog is removed from every data source of /WEB-INF/datasources.xml and its schema
"!   file deleted (unless another catalog still names it), and the work is committed. The views stay: they are per
"!   characteristic, other schemas can use them. Answers the deleted files.
"! It runs as the XMLA endpoint does (the anonymous logon of the node), accept included, for now.
CLASS zzxxmla1_cl_schema_api DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! the path of the API below the ICF node
    CONSTANTS c_path TYPE string VALUE `/schema/api/`.
    CONSTANTS c_schema_folder TYPE string VALUE `/WEB-INF/schema/`.
    TYPES:
      BEGIN OF ty_parameter,
        name  TYPE string,
        value TYPE string,
      END OF ty_parameter,
      ty_t_parameter TYPE STANDARD TABLE OF ty_parameter WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_request,
        method     TYPE string,          " GET, POST, ...
        path       TYPE string,          " below the ICF node: /schema/api/providers
        parameters TYPE ty_t_parameter,  " of the query string, names in lower case
        body       TYPE string,
      END OF ty_request.
    TYPES:
      BEGIN OF ty_result,
        status       TYPE i,
        content_type TYPE string,
        body         TYPE string,
        allow        TYPE string,  " the methods of the resource, for 405
      END OF ty_result.

    "! Whether a path below the ICF node is one of the API.
    CLASS-METHODS is_api
      IMPORTING !path         TYPE string
      RETURNING VALUE(result) TYPE abap_bool.
    METHODS handle
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE ty_result.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CONSTANTS c_json TYPE string VALUE `application/json; charset=utf-8`.
    TYPES:
      "! a request of check or accept that passed the checks
      BEGIN OF ty_checked,
        schema          TYPE zzxxmla1_cl_schema_def=>ty_schema,
        catalog         TYPE string,
        path            TYPE string,  " of the schema file
        datasources     TYPE string,  " the data sources file as it is
        new_datasources TYPE string,  " with the catalog
      END OF ty_checked.
    TYPES:
      BEGIN OF ty_catalog_entry,
        data_source TYPE string,
        name        TYPE string,
        definition  TYPE string,
      END OF ty_catalog_entry,
      ty_t_catalog_entry TYPE STANDARD TABLE OF ty_catalog_entry WITH EMPTY KEY.

    METHODS providers
      RETURNING VALUE(result) TYPE string.
    METHODS proposal
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string
      RAISING   lcx_refused.
    METHODS schemas
      RETURNING VALUE(result) TYPE string
      RAISING   lcx_refused.
    METHODS schema
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string
      RAISING   lcx_refused.
    METHODS check
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string
      RAISING   lcx_refused.
    METHODS accept
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string
      RAISING   lcx_refused.
    METHODS remove
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string
      RAISING   lcx_refused.
    "! Everything accept checks before it changes anything.
    METHODS check_request
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE ty_checked
      RAISING   lcx_refused.
    "! The catalogs of a data sources file, in the order of the file.
    METHODS all_catalogs
      IMPORTING content       TYPE string
      RETURNING VALUE(result) TYPE ty_t_catalog_entry
      RAISING   lcx_refused.
    "! The catalogs of a data sources file, each name once with its first definition (the XMLA endpoint's choice).
    METHODS first_catalogs
      IMPORTING content       TYPE string
      RETURNING VALUE(result) TYPE ty_t_catalog_entry
      RAISING   lcx_refused.
    "! The server's data sources file, refused if it has none.
    METHODS datasources_file
      RETURNING VALUE(result) TYPE zzxxmla1_cl_files=>ty_file
      RAISING   lcx_refused.
    "! The value of a query parameter, initial if it is not there.
    METHODS parameter
      IMPORTING request       TYPE ty_request
                !name         TYPE string
      RETURNING VALUE(result) TYPE string.
    "! A catalog name is a file name too: letters, digits, _, - and . (not first).
    METHODS check_catalog_name
      IMPORTING catalog TYPE string
      RAISING   lcx_refused.
    "! The data sources file with the catalog in its first data source: unchanged if a data source already has the
    "! catalog with this definition, refused if one has it with another.
    METHODS add_catalog
      IMPORTING content       TYPE string
                catalog       TYPE string
                definition    TYPE string
      RETURNING VALUE(result) TYPE string
      RAISING   lcx_refused.
    "! The data sources file without the catalog in any data source: each Catalog element is cut out of the text
    "! (with its line if it has one of its own), so the file keeps its comments and layout; refused if there is no
    "! such catalog, or if the file read back has anything else changed.
    METHODS remove_catalog
      IMPORTING content       TYPE string
                catalog       TYPE string
      RETURNING VALUE(result) TYPE string
      RAISING   lcx_refused.
    "! Loads the catalogs of the data sources file in ZZXXMLA1_CL_SCHEMA as the XMLA endpoint does (the first
    "! definition of a catalog name), with the given schema as the catalog's; refused with the reader's error.
    METHODS check_schema
      IMPORTING datasources TYPE string
                catalog     TYPE string
                schema_xml  TYPE string
      RAISING   lcx_refused.
    "! The table names of the schema's dimensions (shared and private, and the Table of their hierarchies), each
    "! once in the order of the schema; a name that is the DDL source of a view is replaced by its database view.
    METHODS map_tables
      IMPORTING views         TYPE zzxxmla1_cl_bw_view_gen=>ty_t_view OPTIONAL
      CHANGING  !schema       TYPE zzxxmla1_cl_schema_def=>ty_schema
      RETURNING VALUE(result) TYPE string_table.
    METHODS map_dimension
      IMPORTING views     TYPE zzxxmla1_cl_bw_view_gen=>ty_t_view
      CHANGING  dimension TYPE zzxxmla1_cl_schema_def=>ty_dimension
                names     TYPE string_table.
    METHODS map_table
      IMPORTING views TYPE zzxxmla1_cl_bw_view_gen=>ty_t_view
      CHANGING  table TYPE string
                names TYPE string_table.
    "! The characteristic whose view's DDL source is the table name, initial for any other name.
    METHODS characteristic_of
      IMPORTING table         TYPE string
      RETURNING VALUE(result) TYPE string.
    "! The schema as the UI shows it: dimensions with attributes and hierarchies, cubes with dimensions and measures.
    METHODS outline
      IMPORTING !schema       TYPE zzxxmla1_cl_schema_def=>ty_schema
      RETURNING VALUE(result) TYPE string.
    METHODS dimension_json
      IMPORTING dimension     TYPE zzxxmla1_cl_schema_def=>ty_dimension
      RETURNING VALUE(result) TYPE string.
    METHODS cube_json
      IMPORTING cube          TYPE zzxxmla1_cl_schema_def=>ty_cube
      RETURNING VALUE(result) TYPE string.
    "! A JSON string.
    METHODS json
      IMPORTING !value        TYPE csequence
      RETURNING VALUE(result) TYPE string.
    METHODS json_bool
      IMPORTING !value        TYPE abap_bool
      RETURNING VALUE(result) TYPE string.
    "! A UTC time stamp as an ISO 8601 JSON string (seconds), null if initial.
    METHODS json_timestamp
      IMPORTING !value        TYPE timestampl
      RETURNING VALUE(result) TYPE string.
    "! A JSON array of the given values, each already JSON.
    METHODS json_array
      IMPORTING !values       TYPE string_table
      RETURNING VALUE(result) TYPE string.
    METHODS error_result
      IMPORTING status        TYPE i
                !message      TYPE string
      RETURNING VALUE(result) TYPE ty_result.
ENDCLASS.



CLASS zzxxmla1_cl_schema_api IMPLEMENTATION.

  METHOD is_api.
    result = xsdbool( strlen( path ) >= strlen( c_path ) AND substring( val = path len = strlen( c_path ) ) = c_path ).
  ENDMETHOD.

  METHOD handle.
    DATA(resource) = COND string( WHEN is_api( request-path )
                                  THEN substring( val = request-path off = strlen( c_path ) ) ).
    DATA(allow) = SWITCH string( resource WHEN `providers` OR `proposal` OR `schemas` OR `schema` THEN `GET`
                                          WHEN `check` OR `accept` OR `remove` THEN `POST` ).
    IF allow IS INITIAL.
      result = error_result( status = 404 message = |No resource { request-path }| ).
      RETURN.
    ENDIF.
    IF request-method <> allow.
      result = error_result( status = 405 message = |{ request-method } is not allowed on { resource }| ).
      result-allow = allow.
      RETURN.
    ENDIF.
    TRY.
        result-body = SWITCH #( resource WHEN `providers` THEN providers( )
                                         WHEN `proposal`  THEN proposal( request )
                                         WHEN `schemas`   THEN schemas( )
                                         WHEN `schema`    THEN schema( request )
                                         WHEN `check`     THEN check( request )
                                         WHEN `accept`    THEN accept( request )
                                         ELSE                  remove( request ) ).
        result-status = 200.
        result-content_type = c_json.
      CATCH lcx_refused INTO DATA(refused).
        result = error_result( status = refused->status message = refused->message ).
      CATCH cx_root INTO DATA(error) ##CATCH_ALL.
        " a JSON error rather than a dump the UI cannot show
        result = error_result( status = 500 message = error->get_text( ) ).
    ENDTRY.
  ENDMETHOD.

  METHOD providers.
    DATA entries TYPE string_table.
    LOOP AT NEW zzxxmla1_cl_bw_provider( )->providers( ) INTO DATA(entry).
      APPEND |\{"name":{ json( entry-name ) },"kind":{ json( entry-kind ) },"text":{ json( entry-text ) },| &&
             |"infoarea":{ json( entry-infoarea ) }\}| TO entries.
    ENDLOOP.
    result = |\{"providers":{ json_array( entries ) }\}|.
  ENDMETHOD.

  METHOD proposal.
    DATA(name) = parameter( request = request name = `provider` ).
    IF name IS INITIAL.
      RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 400 message = `Parameter provider is missing`.
    ENDIF.
    DATA provider TYPE zzxxmla1_cl_bw_provider=>ty_provider.
    TRY.
        provider = NEW zzxxmla1_cl_bw_provider( )->read( name ).
      CATCH zzxxmla1_cx_bw_provider INTO DATA(error).
        RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 404 message = error->get_text( ).
    ENDTRY.
    DATA proposal TYPE zzxxmla1_cl_schema_proposal=>ty_proposal.
    TRY.
        proposal = NEW zzxxmla1_cl_schema_proposal( )->propose( provider ).
      CATCH zzxxmla1_cx_xom INTO DATA(xom_error).
        RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 500 message = |Proposal not readable: { xom_error->error_message }|.
    ENDTRY.

    DATA notes TYPE string_table.
    LOOP AT proposal-notes INTO DATA(note).
      APPEND |\{"iobjnm":{ json( note-iobjnm ) },"reason":{ json( note-reason ) }\}| TO notes.
    ENDLOOP.
    DATA suggestions TYPE string_table.
    LOOP AT proposal-suggestions INTO DATA(suggestion).
      APPEND |\{"dimension":{ json( suggestion-dimension ) },"attribute":{ json( suggestion-attribute ) },| &&
             |"levelType":{ json( suggestion-level_type ) }\}| TO suggestions.
    ENDLOOP.
    result = |\{"provider":\{"name":{ json( provider-name ) },"kind":{ json( provider-kind ) },| &&
             |"text":{ json( provider-text ) },"infoarea":{ json( provider-infoarea ) },| &&
             |"factTable":{ json( provider-fact_table ) }\},| &&
             |"xml":{ json( proposal-xml ) },"outline":{ outline( proposal-schema ) },| &&
             |"notes":{ json_array( notes ) },"suggestions":{ json_array( suggestions ) }\}|.
  ENDMETHOD.

  METHOD schemas.
    DATA entries TYPE string_table.
    LOOP AT first_catalogs( datasources_file( )-content ) INTO DATA(entry).
      DATA(file) = zzxxmla1_cl_files=>read( entry-definition ).
      APPEND |\{"catalog":{ json( entry-name ) },"dataSource":{ json( entry-data_source ) },| &&
             |"file":{ json( entry-definition ) },"exists":{ json_bool( xsdbool( file-path IS NOT INITIAL ) ) },| &&
             |"changedAt":{ json_timestamp( file-changed_at ) },"changedBy":{ json( file-changed_by ) }\}| TO entries.
    ENDLOOP.
    result = |\{"schemas":{ json_array( entries ) }\}|.
  ENDMETHOD.

  METHOD schema.
    DATA(catalog) = parameter( request = request name = `catalog` ).
    IF catalog IS INITIAL.
      RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 400 message = `Parameter catalog is missing`.
    ENDIF.
    DATA(entries) = first_catalogs( datasources_file( )-content ).
    READ TABLE entries INTO DATA(entry) WITH KEY name = catalog.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 404 message = |No catalog '{ catalog }'|.
    ENDIF.
    DATA(file) = zzxxmla1_cl_files=>read( entry-definition ).
    IF file-path IS INITIAL.
      RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 404
        message = |Catalog '{ catalog }': the schema file { entry-definition } does not exist|.
    ENDIF.
    DATA parsed TYPE zzxxmla1_cl_schema_def=>ty_schema.
    TRY.
        parsed = zzxxmla1_cl_schema_def=>parse( file-content ).
      CATCH zzxxmla1_cx_xom INTO DATA(xom_error).
        RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 500
          message = |Schema file { entry-definition } not readable: { xom_error->error_message }|.
    ENDTRY.
    result = |\{"catalog":{ json( entry-name ) },"dataSource":{ json( entry-data_source ) },| &&
             |"file":{ json( entry-definition ) },"changedAt":{ json_timestamp( file-changed_at ) },| &&
             |"changedBy":{ json( file-changed_by ) },"xml":{ json( file-content ) },"outline":{ outline( parsed ) }\}|.
  ENDMETHOD.

  METHOD check.
    DATA(checked) = check_request( request ).
    DATA(tables) = map_tables( CHANGING schema = checked-schema ).
    DATA characteristics TYPE string_table.
    LOOP AT tables INTO DATA(table).
      DATA(characteristic) = characteristic_of( table ).
      IF characteristic IS NOT INITIAL.
        APPEND json( characteristic ) TO characteristics.
      ENDIF.
    ENDLOOP.
    result = |\{"catalog":{ json( checked-catalog ) },"file":{ json( checked-path ) },| &&
             |"newCatalog":{ json_bool( xsdbool( checked-new_datasources <> checked-datasources ) ) },| &&
             |"views":{ json_array( characteristics ) }\}|.
  ENDMETHOD.

  METHOD check_request.
    TRY.
        result-schema = zzxxmla1_cl_schema_def=>parse( request-body ).
      CATCH zzxxmla1_cx_xom INTO DATA(xom_error).
        RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 400 message = |Schema not readable: { xom_error->error_message }|.
    ENDTRY.
    result-catalog = parameter( request = request name = `catalog` ).
    IF result-catalog IS INITIAL.
      result-catalog = result-schema-name.
    ENDIF.
    check_catalog_name( result-catalog ).
    result-datasources = datasources_file( )-content.
    " an accepted schema edited again goes back to its catalog's file
    DATA(entries) = first_catalogs( result-datasources ).
    READ TABLE entries INTO DATA(existing) WITH KEY name = result-catalog.
    IF sy-subrc = 0.
      result-path = existing-definition.
    ELSE.
      result-path = |{ c_schema_folder }{ result-catalog }.xml|.
    ENDIF.
    result-new_datasources = add_catalog( content = result-datasources catalog = result-catalog definition = result-path ).
    check_schema( datasources = result-new_datasources catalog = result-catalog schema_xml = request-body ).
  ENDMETHOD.

  METHOD accept.
    DATA(checked) = check_request( request ).
    DATA(schema) = checked-schema.
    DATA(catalog) = checked-catalog.
    DATA(path) = checked-path.

    " nothing is changed before this point
    DATA views TYPE zzxxmla1_cl_bw_view_gen=>ty_t_view.
    DATA(generator) = NEW zzxxmla1_cl_bw_view_gen( ).
    DATA(tables) = map_tables( CHANGING schema = schema ).
    LOOP AT tables INTO DATA(table).
      DATA(characteristic) = characteristic_of( table ).
      IF characteristic IS NOT INITIAL.
        TRY.
            APPEND generator->generate( CONV #( characteristic ) ) TO views.
          CATCH cx_dd_ddl_exception INTO DATA(ddl_error).
            RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 500
              message = |View of { characteristic } not generated: { ddl_error->get_text( ) }|.
        ENDTRY.
      ENDIF.
    ENDLOOP.
    " the schema as it came, unless view names had to be put in
    DATA(xml) = request-body.
    IF views IS NOT INITIAL.
      map_tables( EXPORTING views = views CHANGING schema = schema ).
      xml = zzxxmla1_cl_schema_def=>to_xml( schema ).
    ENDIF.
    zzxxmla1_cl_files=>write( path = path content = xml ).
    IF checked-new_datasources <> checked-datasources.
      zzxxmla1_cl_files=>write( path = zzxxmla1_cl_files=>c_datasources content = checked-new_datasources ).
    ENDIF.
    COMMIT WORK.

    DATA view_list TYPE string_table.
    LOOP AT views INTO DATA(view).
      APPEND |\{"characteristic":{ json( view-characteristic ) },"ddlName":{ json( view-ddl_name ) },| &&
             |"viewName":{ json( view-view_name ) }\}| TO view_list.
    ENDLOOP.
    result = |\{"catalog":{ json( catalog ) },"file":{ json( path ) },"views":{ json_array( view_list ) },| &&
             |"xml":{ json( xml ) }\}|.
  ENDMETHOD.

  METHOD remove.
    DATA(catalog) = parameter( request = request name = `catalog` ).
    IF catalog IS INITIAL.
      RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 400 message = `Parameter catalog is missing`.
    ENDIF.
    DATA(datasources) = datasources_file( )-content.
    DATA(new_datasources) = remove_catalog( content = datasources catalog = catalog ).
    " a schema file goes with its catalog, unless another catalog still names it
    DATA(rest) = all_catalogs( new_datasources ).
    DATA files TYPE string_table.
    LOOP AT all_catalogs( datasources ) INTO DATA(entry) WHERE name = catalog.
      IF NOT line_exists( rest[ definition = entry-definition ] )
          AND NOT line_exists( files[ table_line = entry-definition ] )
          AND entry-definition <> zzxxmla1_cl_files=>c_datasources
          AND zzxxmla1_cl_files=>read( entry-definition )-path IS NOT INITIAL.
        APPEND entry-definition TO files.
      ENDIF.
    ENDLOOP.

    " nothing is changed before this point
    zzxxmla1_cl_files=>write( path = zzxxmla1_cl_files=>c_datasources content = new_datasources ).
    DATA removed TYPE string_table.
    LOOP AT files INTO DATA(file).
      zzxxmla1_cl_files=>delete( file ).
      APPEND json( file ) TO removed.
    ENDLOOP.
    COMMIT WORK.
    result = |\{"catalog":{ json( catalog ) },"removedFiles":{ json_array( removed ) }\}|.
  ENDMETHOD.

  METHOD parameter.
    READ TABLE request-parameters INTO DATA(found) WITH KEY name = name.
    IF sy-subrc = 0.
      result = found-value.
    ENDIF.
  ENDMETHOD.

  METHOD all_catalogs.
    DATA data_sources TYPE zzxxmla1_cl_repository=>ty_t_data_source.
    TRY.
        data_sources = zzxxmla1_cl_repository=>of_content( content )->data_sources( ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 500 message = error->description.
    ENDTRY.
    LOOP AT data_sources INTO DATA(data_source).
      LOOP AT data_source-catalogs INTO DATA(catalog).
        APPEND VALUE #( data_source = data_source-name name = catalog-name definition = catalog-definition )
          TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD first_catalogs.
    LOOP AT all_catalogs( content ) INTO DATA(entry).
      IF NOT line_exists( result[ name = entry-name ] ).
        APPEND entry TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD datasources_file.
    result = zzxxmla1_cl_files=>read( zzxxmla1_cl_files=>c_datasources ).
    IF result-path IS INITIAL.
      RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 500 message = |The server has no { zzxxmla1_cl_files=>c_datasources }|.
    ENDIF.
  ENDMETHOD.

  METHOD check_catalog_name.
    IF NOT matches( val = catalog regex = `[A-Za-z0-9_][A-Za-z0-9_.\-]*` ).
      RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 400
        message = |Catalog name '{ catalog }': only letters, digits, _, - and . (not first) are allowed|.
    ENDIF.
  ENDMETHOD.

  METHOD add_catalog.
    DATA data_sources TYPE zzxxmla1_cl_repository=>ty_t_data_source.
    TRY.
        data_sources = zzxxmla1_cl_repository=>of_content( content )->data_sources( ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 500 message = error->description.
    ENDTRY.
    IF data_sources IS INITIAL.
      RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 500
        message = |{ zzxxmla1_cl_files=>c_datasources } has no data source|.
    ENDIF.
    DATA(registered) = abap_false.
    LOOP AT data_sources INTO DATA(data_source).
      LOOP AT data_source-catalogs INTO DATA(existing) WHERE name = catalog.
        IF existing-definition <> definition.
          RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 400
            message = |Catalog '{ catalog }' exists already, with the schema file { existing-definition }|.
        ENDIF.
        registered = abap_true.
      ENDLOOP.
    ENDLOOP.
    IF registered = abap_true.
      result = content.
      RETURN.
    ENDIF.

    " the first data source's Catalogs, indented as its closing tag
    FIND FIRST OCCURRENCE OF `</Catalogs>` IN content MATCH OFFSET DATA(offset).
    IF sy-subrc = 0.
      DATA(before) = substring( val = content len = offset ).
      DATA(line_start) = find( val = before sub = |\n| occ = -1 ) + 1.
      DATA(indent) = substring( val = before off = line_start ).
      IF indent CN ` `.
        indent = ``.
      ENDIF.
      result = before &&
               |  <Catalog name="{ escape( val = catalog format = cl_abap_format=>e_xml_attr ) }">\n| &&
               |{ indent }    <Definition>{ escape( val = definition format = cl_abap_format=>e_xml_text ) }</Definition>\n| &&
               |{ indent }  </Catalog>\n{ indent }| &&
               substring( val = content off = offset ).
    ENDIF.
    " the catalog must now be the first data source's (the first </Catalogs> could have been in a comment)
    TRY.
        DATA(first) = zzxxmla1_cl_repository=>of_content( result )->data_sources( ).
        DATA(added) = abap_false.
        IF first IS NOT INITIAL.
          added = xsdbool( line_exists( first[ 1 ]-catalogs[ name = catalog definition = definition ] ) ).
        ENDIF.
      CATCH zzxxmla1_cx_xmla.
        added = abap_false.
    ENDTRY.
    IF added = abap_false.
      RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 500
        message = |The catalog cannot be added to the Catalogs of the first data source of { zzxxmla1_cl_files=>c_datasources }|.
    ENDIF.
  ENDMETHOD.

  METHOD remove_catalog.
    DATA(before) = all_catalogs( content ).
    DATA(expected) = before.
    DELETE expected WHERE name = catalog.
    IF lines( expected ) = lines( before ).
      RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 404 message = |No catalog '{ catalog }'|.
    ENDIF.

    DATA name TYPE string.
    DATA quote TYPE string.
    result = content.
    DATA(offset) = 0.
    DO.
      " the next Catalog element (not Catalogs) and its end; Definition is required, so it is never empty
      FIND REGEX `<Catalog[\s>]` IN SECTION OFFSET offset OF result MATCH OFFSET DATA(start).
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      FIND `</Catalog>` IN SECTION OFFSET start OF result MATCH OFFSET DATA(close).
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      DATA(stop) = close + strlen( `</Catalog>` ).
      DATA(open_tag) = substring( val = result off = start len = find( val = result sub = `>` off = start ) - start + 1 ).
      CLEAR name.
      FIND REGEX `\sname\s*=\s*(["'])([^"']*)\1` IN open_tag SUBMATCHES quote name.
      IF name <> catalog.
        offset = stop.
        CONTINUE.
      ENDIF.
      " with its line if the element has one of its own: the indent before it, the line break after it
      DATA(from) = start.
      WHILE from > 0 AND substring( val = result off = from - 1 len = 1 ) CA | \t|.
        from = from - 1.
      ENDWHILE.
      DATA(to) = stop.
      WHILE to < strlen( result ) AND substring( val = result off = to len = 1 ) CA | \t\r|.
        to = to + 1.
      ENDWHILE.
      IF ( from = 0 OR substring( val = result off = from - 1 len = 1 ) = |\n| )
          AND to < strlen( result ) AND substring( val = result off = to len = 1 ) = |\n|.
        to = to + 1.
      ELSE.
        from = start.
        to = stop.
      ENDIF.
      result = substring( val = result len = from ) && substring( val = result off = to ).
      offset = from.
    ENDDO.

    " read back: the catalog is gone and nothing else changed (a Catalog in a comment, an escaped name, ...)
    DATA(removed) = abap_false.
    TRY.
        removed = xsdbool( all_catalogs( result ) = expected AND result <> content ).
      CATCH lcx_refused.
        removed = abap_false.
    ENDTRY.
    IF removed = abap_false.
      RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 500
        message = |Catalog '{ catalog }' cannot be removed from the text of { zzxxmla1_cl_files=>c_datasources }|.
    ENDIF.
  ENDMETHOD.

  METHOD check_schema.
    DATA catalogs TYPE zzxxmla1_cl_schema=>ty_t_catalog.
    LOOP AT first_catalogs( datasources ) INTO DATA(entry).
      IF entry-name = catalog.
        APPEND VALUE #( name = entry-name schema = schema_xml ) TO catalogs.
      ELSE.
        DATA(file) = zzxxmla1_cl_files=>read( entry-definition ).
        IF file-path IS INITIAL.
          RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 500
            message = |Catalog '{ entry-name }': the schema file { entry-definition } does not exist|.
        ENDIF.
        APPEND VALUE #( name = entry-name schema = file-content updated_at = file-changed_at ) TO catalogs.
      ENDIF.
    ENDLOOP.
    TRY.
        zzxxmla1_cl_schema=>of_catalogs( catalogs ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        RAISE EXCEPTION TYPE lcx_refused EXPORTING status = 400 message = error->description.
    ENDTRY.
  ENDMETHOD.

  METHOD map_tables.
    LOOP AT schema-dimensions ASSIGNING FIELD-SYMBOL(<dimension>).
      map_dimension( EXPORTING views = views CHANGING dimension = <dimension> names = result ).
    ENDLOOP.
    LOOP AT schema-cubes INTO DATA(cube).
      LOOP AT cube-dimensions INTO DATA(node) WHERE name = `Dimension`.
        " the node refers to the dimension, so it changes in the schema
        DATA(own) = CAST zzxxmla1_cl_schema_def=>ty_dimension( node-def ).
        map_dimension( EXPORTING views = views CHANGING dimension = own->* names = result ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD map_dimension.
    map_table( EXPORTING views = views CHANGING table = dimension-table names = names ).
    LOOP AT dimension-hierarchies INTO DATA(hierarchy) WHERE relation-name = `Table`.
      DATA(table) = CAST zzxxmla1_cl_schema_def=>ty_table( hierarchy-relation-def ).
      map_table( EXPORTING views = views CHANGING table = table->name names = names ).
    ENDLOOP.
  ENDMETHOD.

  METHOD map_table.
    IF table IS INITIAL.
      RETURN.
    ENDIF.
    IF NOT line_exists( names[ table_line = table ] ).
      APPEND table TO names.
    ENDIF.
    READ TABLE views INTO DATA(view) WITH KEY ddl_name = table.
    IF sy-subrc = 0.
      table = view-view_name.
    ENDIF.
  ENDMETHOD.

  METHOD characteristic_of.
    DATA(prefix) = zzxxmla1_cl_bw_view_gen=>ddl_name( `` ).
    DATA(length) = strlen( prefix ).
    IF strlen( table ) > length AND substring( val = table len = length ) = prefix.
      result = substring( val = table off = length ).
    ENDIF.
  ENDMETHOD.

  METHOD outline.
    DATA dimensions TYPE string_table.
    LOOP AT schema-dimensions INTO DATA(dimension).
      APPEND dimension_json( dimension ) TO dimensions.
    ENDLOOP.
    DATA cubes TYPE string_table.
    LOOP AT schema-cubes INTO DATA(cube).
      APPEND cube_json( cube ) TO cubes.
    ENDLOOP.
    result = |\{"name":{ json( schema-name ) },"dimensions":{ json_array( dimensions ) },| &&
             |"cubes":{ json_array( cubes ) }\}|.
  ENDMETHOD.

  METHOD dimension_json.
    DATA attributes TYPE string_table.
    LOOP AT dimension-attributes INTO DATA(attribute).
      DATA(key_column) = COND string( WHEN attribute-key_column IS BOUND THEN attribute-key_column->column_name ).
      DATA(name_column) = COND string( WHEN attribute-name_column IS BOUND THEN attribute-name_column->column_name ).
      APPEND |\{"name":{ json( attribute-name ) },"usage":{ json( attribute-usage ) },| &&
             |"keyColumn":{ json( key_column ) },"nameColumn":{ json( name_column ) },| &&
             |"levelType":{ json( attribute-level_type ) }\}| TO attributes.
    ENDLOOP.
    DATA hierarchies TYPE string_table.
    LOOP AT dimension-hierarchies INTO DATA(hierarchy).
      DATA(levels) = VALUE string_table( ).
      LOOP AT hierarchy-levels INTO DATA(level).
        APPEND |\{"name":{ json( level-name ) },"sourceAttribute":{ json( level-source_attribute ) },| &&
               |"levelType":{ json( level-level_type ) }\}| TO levels.
      ENDLOOP.
      APPEND |\{"name":{ json( hierarchy-name ) },"hasAll":{ json_bool( hierarchy-has_all ) },| &&
             |"defaultMember":{ json( hierarchy-default_member ) },"levels":{ json_array( levels ) }\}| TO hierarchies.
    ENDLOOP.
    result = |\{"name":{ json( dimension-name ) },"type":{ json( dimension-type ) },| &&
             |"table":{ json( dimension-table ) },"attributes":{ json_array( attributes ) },| &&
             |"hierarchies":{ json_array( hierarchies ) }\}|.
  ENDMETHOD.

  METHOD cube_json.
    DATA fact_table TYPE string.
    IF cube-fact-name = `Table`.
      DATA(fact) = CAST zzxxmla1_cl_schema_def=>ty_table( cube-fact-def ).
      fact_table = fact->name.
    ENDIF.
    DATA dimensions TYPE string_table.
    LOOP AT cube-dimensions INTO DATA(node).
      CASE node-name.
        WHEN `DimensionUsage`.
          DATA(usage) = CAST zzxxmla1_cl_schema_def=>ty_dimension_usage( node-def ).
          APPEND |\{"name":{ json( usage->name ) },"source":{ json( usage->source ) },| &&
                 |"foreignKey":{ json( usage->foreign_key ) }\}| TO dimensions.
        WHEN `Dimension`.
          DATA(own) = CAST zzxxmla1_cl_schema_def=>ty_dimension( node-def ).
          APPEND |\{"name":{ json( own->name ) },"foreignKey":{ json( own->foreign_key ) },| &&
                 |"dimension":{ dimension_json( own->* ) }\}| TO dimensions.
      ENDCASE.
    ENDLOOP.
    DATA measures TYPE string_table.
    LOOP AT cube-measures INTO DATA(measure).
      APPEND |\{"name":{ json( measure-name ) },"column":{ json( measure-column ) },| &&
             |"aggregator":{ json( measure-aggregator ) },"formatString":{ json( measure-format_string ) }\}|
        TO measures.
    ENDLOOP.
    result = |\{"name":{ json( cube-name ) },"caption":{ json( cube-caption ) },"factTable":{ json( fact_table ) },| &&
             |"defaultMeasure":{ json( cube-default_measure ) },"dimensions":{ json_array( dimensions ) },| &&
             |"measures":{ json_array( measures ) }\}|.
  ENDMETHOD.

  METHOD json.
    result = |"{ escape( val = value format = cl_abap_format=>e_json_string ) }"|.
  ENDMETHOD.

  METHOD json_bool.
    result = COND #( WHEN value = abap_true THEN `true` ELSE `false` ).
  ENDMETHOD.

  METHOD json_timestamp.
    IF value IS INITIAL.
      result = `null`.
      RETURN.
    ENDIF.
    DATA(seconds) = CONV timestamp( value ).
    result = |"{ seconds TIMESTAMP = ISO }Z"|.
  ENDMETHOD.

  METHOD json_array.
    result = |[{ concat_lines_of( table = values sep = `,` ) }]|.
  ENDMETHOD.

  METHOD error_result.
    result = VALUE #( status = status content_type = c_json body = |\{"error":{ json( message ) }\}| ).
  ENDMETHOD.

ENDCLASS.