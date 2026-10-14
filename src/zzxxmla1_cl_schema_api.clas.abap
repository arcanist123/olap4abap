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
"!   with the notes, the time suggestions and the NUMC columns of its views that have a number (COLUMN_INT), which the
"!   UI names in their place when a dimension is switched to numbers, and the cube's characteristics (below). Only
"!   the defaults are restricted (ZZXXMLA1_CL_SCHEMA_DEFAULTS: with 0FISCYEAR or 0FISCPER the variant fixed to K4, the
"!   periods restricted to the regular ones, both time dimensions; its notes join the proposal's); any other
"!   selection is an edit (fix);
"! - A selection (docs/bw-schema-design-guide.md, section 3.8) is given by parameters, one per characteristic:
"!   filter.CHARACTERISTIC=rows (filter the cube), members.CHARACTERISTIC=rows (restrict members), the rows as the
"!   annotations write them (I EQ 'K4';E CP '*013'), and fixed.CHARACTERISTIC=value, filter the cube with I EQ value;
"!   a characteristic given twice or rows that do not parse are refused (400);
"! - GET values?characteristic=C: the values C can be restricted to (its SID table, at most 500, more: true if there
"!   are more), under the selection of its compounding where the parameters give one;
"! - POST fix?cube=X&filter.CHARACTERISTIC=rows...: the body is the edited schema XML; the cube (without cube the
"!   first one) restricts characteristics by the given selection, all it restricts, its tables and columns following
"!   (ZZXXMLA1_CL_SCHEMA_FIX); answers the new XML and outline, the tables replaced, the NUMC numbers of the
"!   characteristics' tables and the cube's characteristics; 400 if the selection or the schema is refused, or if the
"!   probe of the cube's facts refuses the selection (ZZXXMLA1_CL_SCHEMA_PROBE: its facts hold a value that a
"!   selection in restrict members excludes). Nothing is changed on the server;
"! - GET schemas: the catalogs of /WEB-INF/datasources.xml, each name once (its first definition, as the XMLA endpoint
"!   reads them), with their schema files;
"! - GET schema?catalog=X: the catalog's schema as XML and as an outline, to edit an accepted schema again, with the
"!   columns of its tables that have a number (a column COLUMN_INT next to COLUMN, from the dictionary) and the
"!   cube's characteristics;
"!   The cube's characteristics (of its first cube) are those of its provider that can be restricted, with the
"!   dimension of the cube on each and its selection (mode filter or members, rows, their text; fixed and value for
"!   one I EQ value); none if the provider is not found (a schema not on BW's tables);
"! - POST check?catalog=X: the body is the edited schema XML. The checks of accept, nothing is changed: the schema
"!   parses, and the server's catalogs with this one load in ZZXXMLA1_CL_SCHEMA as the XMLA endpoint will load them.
"!   The schema file of an existing catalog is its Definition (it is replaced), of a new one
"!   /WEB-INF/schema/<catalog>.xml. Answers the file, whether the catalog is new and the characteristics (and aDSOs,
"!   for their fact views) whose views accept generates. With probe=true (the check before accept, not the one run
"!   while the user types) the cubes' facts are probed too, as accept probes them, and the answer has the probe;
"!   Check also refuses views generated for another selection than the one of the cube that uses them (its
"!   annotations olap4abap.filter.CHARACTERISTIC and olap4abap.members.CHARACTERISTIC, edited by hand), a cube that
"!   filters on characteristics on facts that are not its fact view, and a table that cubes with different selections
"!   of it use;
"! - POST accept?catalog=X: the checks of check and the probe, then the views of the tables named by a placeholder
"!   (ZZXXMLA1_C_<characteristic>, ZZXXMLA1_F_<provider> for the fact view of an aDSO with a compounded characteristic
"!   or of a cube that filters on characteristics) are generated (ZZXXMLA1_CL_BW_VIEW_GEN) for the selection of the
"!   cube that uses them and replaced by their database views,
"!   the schema file is written, a new catalog added to the first data source of /WEB-INF/datasources.xml, and the
"!   work is committed. Without catalog the schema's name is the catalog. Then the views of selections that no
"!   catalog's schema names any more are deleted (answered as deletedViews);
"! - POST remove?catalog=X: the catalog is removed from every data source of /WEB-INF/datasources.xml and its schema
"!   file deleted (unless another catalog still names it), and the work is committed. The plain views stay: they are
"!   per characteristic, other schemas can use them; the views of selections that no catalog's schema names any more
"!   are deleted. Answers the deleted files and views;
"! - POST probe[?catalog=X]: the probe of every catalog's cubes (or of one catalog's), nothing written:
"!   {catalogs: [{catalog, ok, cubes: [{cube, ok, characteristics: [{name, ok, values: [{value, facts}]}]}]}],
"!   runtime} (milliseconds); a catalog that cannot be probed (its schema file missing or unreadable, a cube that
"!   restricts members not on a BW provider's facts) is an entry with error and no cubes, the others are probed;
"! - GET time?from=YYYY-MM-DD&to=YYYY-MM-DD: the master data of the calendar time characteristics
"!   (ZZXXMLA1_CL_TIME_MD): the interval (without from and to BW's, the one of RSRHIERARCHYVIRT) and, per
"!   characteristic, its values with SID and with attributes and those of the interval that are missing;
"! - POST time/fill?from=...&to=...&characteristics=0CALMONTH,0CALYEAR: makes the SIDs of the interval's values and
"!   writes the attribute rows (without characteristics all of them), committed per characteristic. Answers what was
"!   done and the state afterwards.
"! - GET trace[?filter=U]: the trace of the XMLA endpoint (ZZXXMLA1_CL_TRACE): the current user, the users with the
"!   trace on and the traced calls (of user U), newest first, without request and response;
"! - GET trace/entry?id=X: a traced call with its SOAP request, its MDX and its SOAP response (unzipped, the first
"!   million characters; responseTruncated if there are more); GET trace/response?id=X: all of the response, text/xml;
"! - POST trace/on?user=U (for ZZXXMLA1_CL_TRACE=>C_ACTIVE_HOURS from now, deleting the calls older than its
"!   C_RETENTION_DAYS), trace/off?user=U (without user the current one), trace/clear[?user=U] (without user everyone's
"!   calls): committed, answered as GET trace.
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
    "! how much of a traced response GET trace/entry gives (characters); GET trace/response gives all of it
    CONSTANTS c_trace_shown TYPE i VALUE 1000000.
    TYPES:
      "! a request of check or accept that passed the checks
      BEGIN OF ty_checked,
        schema          TYPE zzxxmla1_cl_schema_def=>ty_schema,
        catalog         TYPE string,
        path            TYPE string,  " of the schema file
        datasources     TYPE string,  " the data sources file as it is
        new_datasources TYPE string,  " with the catalog
        probed          TYPE zzxxmla1_cl_schema_probe=>ty_t_cube,  " if probed
      END OF ty_checked.
    TYPES:
      "! a table of a schema whose view the API knows (a placeholder or a view of table ZZXXMLA1_VIEW): the
      "! characteristic or provider (kind C or F) of its view, the selection of the cube that uses it (cube) and the
      "! selection of its view for that (view, as table ZZXXMLA1_VIEW keys it)
      BEGIN OF ty_table_selection,
        table     TYPE string,
        kind      TYPE c LENGTH 1,
        object    TYPE string,
        cube      TYPE zzxxmla1_cl_bw_view_gen=>ty_t_selection,
        selection TYPE string,
      END OF ty_table_selection,
      ty_t_table_selection TYPE STANDARD TABLE OF ty_table_selection WITH EMPTY KEY.
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
      RAISING   zzxxmla1_cx_api_refused.
    METHODS values
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_api_refused.
    METHODS fix
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_api_refused.
    "! The provider and the characteristics of the schema's first cube as JSON members (without braces): the
    "! provider read for the cube's selection, or initial to read it (null and none if it is not found).
    METHODS characteristics_json
      IMPORTING !schema       TYPE zzxxmla1_cl_schema_def=>ty_schema
                provider      TYPE zzxxmla1_cl_bw_provider=>ty_provider OPTIONAL
      RETURNING VALUE(result) TYPE string.
    "! The selection of a request's parameters filter.CHARACTERISTIC=rows, members.CHARACTERISTIC=rows and
    "! fixed.CHARACTERISTIC=value; refused if rows do not parse or a characteristic is given twice.
    METHODS selection_parameters
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_view_gen=>ty_t_selection
      RAISING   zzxxmla1_cx_api_refused.
    "! The selection of a cube's annotations; refused (400) if it is none.
    METHODS cube_selection
      IMPORTING cube          TYPE zzxxmla1_cl_schema_def=>ty_cube
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_view_gen=>ty_t_selection
      RAISING   zzxxmla1_cx_api_refused.
    METHODS schemas
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_api_refused.
    METHODS schema
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_api_refused.
    METHODS check
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_api_refused.
    METHODS accept
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_api_refused.
    METHODS remove
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_api_refused.
    METHODS probe
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_api_refused.
    "! The probe of every cube of a schema; refused (400) if the probe refuses one, or if a cube that restricts members
    "! is on no BW provider's facts.
    METHODS probe_schema
      IMPORTING !schema       TYPE zzxxmla1_cl_schema_def=>ty_schema
      RETURNING VALUE(result) TYPE zzxxmla1_cl_schema_probe=>ty_t_cube
      RAISING   zzxxmla1_cx_api_refused.
    "! Probed cubes as a JSON array.
    METHODS cubes_json
      IMPORTING cubes         TYPE zzxxmla1_cl_schema_probe=>ty_t_cube
      RETURNING VALUE(result) TYPE string.
    METHODS time_status
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_api_refused.
    METHODS fill_time
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_api_refused.
    "! GET trace[?filter=U]: the current user, the users with the trace on and the traced calls (of U), newest first.
    METHODS trace_status
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_api_refused.
    "! GET trace/entry?id=X: a traced call with its SOAP request and its SOAP response, unzipped (the first
    "! c_trace_shown characters of it); refused (404) if there is none.
    METHODS trace_entry
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_api_refused.
    "! GET trace/response?id=X: the SOAP response of a traced call as it was sent (text/xml).
    METHODS trace_response
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_api_refused.
    "! POST trace/on?user=U, trace/off?user=U (without user the current one) and trace/clear[?user=U] (without user
    "! everyone's calls); committed, answered as GET trace.
    METHODS switch_trace
      IMPORTING request       TYPE ty_request
                resource      TYPE string
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_api_refused.
    "! A user name parameter in upper case; the fallback if it is not given, refused (400) if it is no user name.
    METHODS user_parameter
      IMPORTING request       TYPE ty_request
                !name         TYPE string
                fallback      TYPE syuname OPTIONAL
      RETURNING VALUE(result) TYPE syuname
      RAISING   zzxxmla1_cx_api_refused.
    "! The traced call of the parameter id; refused (400 without id, 404 if there is none).
    METHODS traced_call
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE zzxxmla1_cl_trace=>ty_detail
      RAISING   zzxxmla1_cx_api_refused.
    "! A traced call as JSON members (without braces).
    METHODS trace_entry_json
      IMPORTING entry         TYPE zzxxmla1_cl_trace=>ty_entry
      RETURNING VALUE(result) TYPE string.
    "! The interval of the parameters from and to (YYYY-MM-DD or YYYYMMDD), each BW's if it is not given; refused if
    "! a date is none, from is after to, or the interval is longer than 100 years.
    METHODS time_interval
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE zzxxmla1_cl_time_md=>ty_interval
      RAISING   zzxxmla1_cx_api_refused.
    "! A date parameter as a date, initial if it is not given.
    METHODS date_parameter
      IMPORTING request       TYPE ty_request
                !name         TYPE string
      RETURNING VALUE(result) TYPE d
      RAISING   zzxxmla1_cx_api_refused.
    "! The interval and the state of every time characteristic as JSON members (without braces).
    METHODS time_status_json
      IMPORTING time_md       TYPE REF TO zzxxmla1_cl_time_md
                !interval     TYPE zzxxmla1_cl_time_md=>ty_interval
      RETURNING VALUE(result) TYPE string.
    "! A date as a JSON string YYYY-MM-DD.
    METHODS json_date
      IMPORTING !value        TYPE d
      RETURNING VALUE(result) TYPE string.
    "! Everything accept checks before it changes anything; probe: the probe of the cubes' facts too.
    METHODS check_request
      IMPORTING request       TYPE ty_request
                probe         TYPE abap_bool
      RETURNING VALUE(result) TYPE ty_checked
      RAISING   zzxxmla1_cx_api_refused.
    "! The catalogs of a data sources file, in the order of the file.
    METHODS all_catalogs
      IMPORTING content       TYPE string
      RETURNING VALUE(result) TYPE ty_t_catalog_entry
      RAISING   zzxxmla1_cx_api_refused.
    "! The catalogs of a data sources file, each name once with its first definition (the XMLA endpoint's choice).
    METHODS first_catalogs
      IMPORTING content       TYPE string
      RETURNING VALUE(result) TYPE ty_t_catalog_entry
      RAISING   zzxxmla1_cx_api_refused.
    "! The server's data sources file, refused if it has none.
    METHODS datasources_file
      RETURNING VALUE(result) TYPE zzxxmla1_cl_files=>ty_file
      RAISING   zzxxmla1_cx_api_refused.
    "! The value of a query parameter, initial if it is not there.
    METHODS parameter
      IMPORTING request       TYPE ty_request
                !name         TYPE string
      RETURNING VALUE(result) TYPE string.
    "! A catalog name is a file name too: letters, digits, _, - and . (not first).
    METHODS check_catalog_name
      IMPORTING catalog TYPE string
      RAISING   zzxxmla1_cx_api_refused.
    "! The data sources file with the catalog in its first data source: unchanged if a data source already has the
    "! catalog with this definition, refused if one has it with another.
    METHODS add_catalog
      IMPORTING content       TYPE string
                catalog       TYPE string
                definition    TYPE string
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_api_refused.
    "! The data sources file without the catalog in any data source: each Catalog element is cut out of the text
    "! (with its line if it has one of its own), so the file keeps its comments and layout; refused if there is no
    "! such catalog, or if the file read back has anything else changed.
    METHODS remove_catalog
      IMPORTING content       TYPE string
                catalog       TYPE string
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_api_refused.
    "! Loads the catalogs of the data sources file in ZZXXMLA1_CL_SCHEMA as the XMLA endpoint does (the first
    "! definition of a catalog name), with the given schema as the catalog's; refused with the reader's error.
    METHODS check_schema
      IMPORTING datasources TYPE string
                catalog     TYPE string
                schema_xml  TYPE string
      RAISING   zzxxmla1_cx_api_refused.
    "! The table names of the schema's dimensions (shared and private, and the Table of their hierarchies) and of its
    "! cubes' fact tables, each once in the order of the schema; a placeholder of a view not generated yet is replaced
    "! by its database view.
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
    "! The characteristic whose view the table name is a placeholder of, or the provider whose fact view it is a
    "! placeholder of (the views list it as characteristic); initial for any other name.
    METHODS characteristic_of
      IMPORTING table         TYPE string
      RETURNING VALUE(result) TYPE string.
    "! The tables of the schema whose views the API knows, with the selection each view needs for the cubes that use
    "! it: a cube's fact table that of the characteristics that filter the cube, a dimension's table that of its
    "! characteristic and its compounding (none for a dimension no cube uses). Refused if two cubes need two different
    "! ones of a table, or if a cube that filters on characteristics is not on a fact view.
    METHODS table_selections
      IMPORTING !schema       TYPE zzxxmla1_cl_schema_def=>ty_schema
      RETURNING VALUE(result) TYPE ty_t_table_selection
      RAISING   zzxxmla1_cx_api_refused.
    "! Adds a table and the selection its view needs for the selection of a cube; refused if it needs another one
    "! already.
    METHODS add_table_selection
      IMPORTING table         TYPE string
                selection     TYPE zzxxmla1_cl_bw_view_gen=>ty_t_selection
                registered    TYPE zzxxmla1_cl_bw_view_gen=>ty_t_view
      CHANGING  selections    TYPE ty_t_table_selection
      RAISING   zzxxmla1_cx_api_refused.
    "! Refuses a schema that names a view of table ZZXXMLA1_VIEW generated for another selection than the one the
    "! cubes that use it need.
    METHODS check_selections
      IMPORTING !schema TYPE zzxxmla1_cl_schema_def=>ty_schema
      RAISING   zzxxmla1_cx_api_refused.
    "! Deletes the views of selections that no schema of a catalog of the data sources names; nothing if a schema
    "! cannot be read. Returns the deleted database views.
    METHODS delete_unused_views
      IMPORTING datasources   TYPE string
      RETURNING VALUE(result) TYPE string_table.
    "! The columns of the tables that have a number, a column COLUMN_INT next to COLUMN (DD03L), with its data type.
    METHODS int_columns
      IMPORTING tables        TYPE string_table
      RETURNING VALUE(result) TYPE zzxxmla1_cl_schema_proposal=>ty_t_int_column.
    METHODS int_columns_json
      IMPORTING int_columns   TYPE zzxxmla1_cl_schema_proposal=>ty_t_int_column
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
    DATA(allow) = SWITCH string( resource WHEN `providers` OR `proposal` OR `values` OR `schemas` OR `schema` OR `time`
                                            OR `trace` OR `trace/entry` OR `trace/response`
                                          THEN `GET`
                                          WHEN `check` OR `accept` OR `remove` OR `fix` OR `probe` OR `time/fill`
                                            OR `trace/on` OR `trace/off` OR `trace/clear`
                                          THEN `POST` ).
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
                                         WHEN `values`    THEN values( request )
                                         WHEN `schemas`   THEN schemas( )
                                         WHEN `schema`    THEN schema( request )
                                         WHEN `check`     THEN check( request )
                                         WHEN `accept`    THEN accept( request )
                                         WHEN `fix`       THEN fix( request )
                                         WHEN `probe`     THEN probe( request )
                                         WHEN `time`      THEN time_status( request )
                                         WHEN `time/fill` THEN fill_time( request )
                                         WHEN `trace`     THEN trace_status( request )
                                         WHEN `trace/entry` THEN trace_entry( request )
                                         WHEN `trace/response` THEN trace_response( request )
                                         WHEN `trace/on` OR `trace/off` OR `trace/clear`
                                                          THEN switch_trace( request = request resource = resource )
                                         ELSE                  remove( request ) ).
        result-status = 200.
        result-content_type = COND #( WHEN resource = `trace/response` THEN `text/xml; charset=utf-8` ELSE c_json ).
      CATCH zzxxmla1_cx_api_refused INTO DATA(refused).
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
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400 message = `Parameter provider is missing`.
    ENDIF.
    DATA provider TYPE zzxxmla1_cl_bw_provider=>ty_provider.
    DATA defaults TYPE zzxxmla1_cl_schema_defaults=>ty_defaults.
    DATA(reader) = NEW zzxxmla1_cl_bw_provider( ).
    TRY.
        provider = reader->read( name ).
        " the fiscal year variant fixed to K4, the periods restricted to the regular ones, both marked as time
        defaults = NEW zzxxmla1_cl_schema_defaults( )->propose( provider ).
        IF defaults-selection IS NOT INITIAL.
          provider = reader->read( name = name selection = defaults-selection ).
        ENDIF.
      CATCH zzxxmla1_cx_bw_provider INTO DATA(error).
        RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 404 message = error->get_text( ).
    ENDTRY.
    DATA proposal TYPE zzxxmla1_cl_schema_proposal=>ty_proposal.
    TRY.
        proposal = NEW zzxxmla1_cl_schema_proposal( )->propose( provider = provider time = defaults-time ).
      CATCH zzxxmla1_cx_xom INTO DATA(xom_error).
        RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 500 message = |Proposal not readable: { xom_error->error_message }|.
    ENDTRY.
    APPEND LINES OF defaults-notes TO proposal-notes.

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
             |"notes":{ json_array( notes ) },"suggestions":{ json_array( suggestions ) },| &&
             |"intColumns":{ int_columns_json( proposal-int_columns ) },| &&
             |{ characteristics_json( schema = proposal-schema provider = provider ) }\}|.
  ENDMETHOD.

  METHOD fix.
    DATA parsed TYPE zzxxmla1_cl_schema_def=>ty_schema.
    TRY.
        parsed = zzxxmla1_cl_schema_def=>parse( request-body ).
      CATCH zzxxmla1_cx_xom INTO DATA(xom_error).
        RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400 message = |Schema not readable: { xom_error->error_message }|.
    ENDTRY.
    DATA(cube) = parameter( request = request name = `cube` ).
    IF cube IS INITIAL.
      cube = VALUE #( parsed-cubes[ 1 ]-name OPTIONAL ).
    ENDIF.
    DATA changes TYPE zzxxmla1_cl_schema_fix=>ty_result.
    TRY.
        changes = NEW zzxxmla1_cl_schema_fix( )->fix( EXPORTING cube      = cube
                                                                selection = selection_parameters( request )
                                                      CHANGING  schema    = parsed ).
      CATCH zzxxmla1_cx_bw_provider INTO DATA(error).
        RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400 message = error->get_text( ).
    ENDTRY.
    " the facts of the cube for the new selection
    DATA(refusal) = zzxxmla1_cl_schema_probe=>refusal( VALUE #(
      ( cube            = cube
        characteristics = NEW zzxxmla1_cl_schema_probe( )->probe( provider  = changes-provider-name
                                                                  selection = changes-provider-selection ) ) ) ).
    IF refusal IS NOT INITIAL.
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400 message = refusal.
    ENDIF.
    DATA tables TYPE string_table.
    LOOP AT changes-tables INTO DATA(replaced).
      APPEND |\{"from":{ json( replaced-from ) },"to":{ json( replaced-to ) }\}| TO tables.
    ENDLOOP.
    result = |\{"xml":{ json( zzxxmla1_cl_schema_def=>to_xml( parsed ) ) },| &&
             |"outline":{ outline( parsed ) },"tables":{ json_array( tables ) },| &&
             |"intColumns":{ int_columns_json( changes-int_columns ) },| &&
             |{ characteristics_json( schema = parsed provider = changes-provider ) }\}|.
  ENDMETHOD.

  METHOD characteristics_json.
    READ TABLE schema-cubes INTO DATA(cube) INDEX 1.
    DATA(read) = provider.
    IF read IS INITIAL AND sy-subrc = 0.
      TRY.
          read = NEW zzxxmla1_cl_schema_fix( )->read_provider( cube ).
        CATCH zzxxmla1_cx_bw_provider.
          CLEAR read.
      ENDTRY.
    ENDIF.
    DATA entries TYPE string_table.
    IF read IS NOT INITIAL.
      LOOP AT zzxxmla1_cl_schema_fix=>characteristics( cube = cube provider = read ) INTO DATA(characteristic).
        DATA(rows) = VALUE string_table( FOR r IN characteristic-rows
                                         ( |\{"sign":{ json( r-sign ) },"option":{ json( r-option ) },| &&
                                           |"low":{ json( r-low ) },"high":{ json( r-high ) }\}| ) ).
        DATA(mode) = SWITCH string( characteristic-mode WHEN zzxxmla1_cl_bw_selection=>c_mode-filter THEN `filter`
                                                        WHEN zzxxmla1_cl_bw_selection=>c_mode-members THEN `members` ).
        APPEND |\{"name":{ json( characteristic-name ) },"text":{ json( characteristic-text ) },| &&
               |"compounding":{ json_array( VALUE #( FOR c IN characteristic-compounding ( json( c ) ) ) ) },| &&
               |"foreignKey":{ json( characteristic-foreign_key ) },| &&
               |"dimension":{ json( characteristic-dimension ) },"shared":{ json_bool( characteristic-shared ) },| &&
               |"mode":{ COND #( WHEN mode IS INITIAL THEN `null` ELSE json( mode ) ) },| &&
               |"rows":{ json_array( rows ) },| &&
               |"selection":{ json( zzxxmla1_cl_bw_selection=>rows_text( characteristic-rows ) ) },| &&
               |"fixed":{ json_bool( characteristic-fixed ) },"value":{ json( characteristic-value ) }\}| TO entries.
      ENDLOOP.
    ENDIF.
    result = |"providerName":{ COND #( WHEN read IS INITIAL THEN `null` ELSE json( read-name ) ) },| &&
             |"cube":{ json( cube-name ) },"characteristics":{ json_array( entries ) }|.
  ENDMETHOD.

  METHOD selection_parameters.
    LOOP AT request-parameters INTO DATA(given).
      DATA(restricted) = VALUE zzxxmla1_cl_bw_selection=>ty_characteristic( ).
      TRY.
          IF given-name CP 'filter.*' OR given-name CP 'members.*' OR given-name CP 'fixed.*'.
            restricted = zzxxmla1_cl_bw_selection=>from_annotation( name  = |olap4abap.{ given-name }|
                                                                     value = given-value ).
          ENDIF.
        CATCH zzxxmla1_cx_bw_provider INTO DATA(error).
          RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400 message = error->get_text( ).
      ENDTRY.
      IF restricted IS INITIAL.
        CONTINUE.
      ENDIF.
      restricted-iobjnm = to_upper( restricted-iobjnm ).
      INSERT restricted INTO TABLE result.
      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400
          message = |{ restricted-iobjnm } has two selections|.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD cube_selection.
    TRY.
        result = zzxxmla1_cl_schema_fix=>cube_selection( cube ).
      CATCH zzxxmla1_cx_bw_provider INTO DATA(error).
        RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400 message = error->get_text( ).
    ENDTRY.
  ENDMETHOD.

  METHOD values.
    CONSTANTS c_max_values TYPE i VALUE 500.
    DATA(characteristic) = to_upper( parameter( request = request name = `characteristic` ) ).
    IF characteristic IS INITIAL.
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400 message = `Parameter characteristic is missing`.
    ENDIF.
    DATA found TYPE string_table.
    TRY.
        found = NEW zzxxmla1_cl_bw_provider( )->values( characteristic = characteristic
                                                         selection      = selection_parameters( request )
                                                         max_values     = c_max_values ).
      CATCH zzxxmla1_cx_bw_provider INTO DATA(error).
        RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400 message = error->get_text( ).
    ENDTRY.
    DATA(more) = xsdbool( lines( found ) > c_max_values ).
    IF more = abap_true.
      DELETE found FROM lines( found ).
    ENDIF.
    result = |\{"characteristic":{ json( characteristic ) },| &&
             |"values":{ json_array( VALUE #( FOR v IN found ( json( v ) ) ) ) },"more":{ json_bool( more ) }\}|.
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
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400 message = `Parameter catalog is missing`.
    ENDIF.
    DATA(entries) = first_catalogs( datasources_file( )-content ).
    READ TABLE entries INTO DATA(entry) WITH KEY name = catalog.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 404 message = |No catalog '{ catalog }'|.
    ENDIF.
    DATA(file) = zzxxmla1_cl_files=>read( entry-definition ).
    IF file-path IS INITIAL.
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 404
        message = |Catalog '{ catalog }': the schema file { entry-definition } does not exist|.
    ENDIF.
    DATA parsed TYPE zzxxmla1_cl_schema_def=>ty_schema.
    TRY.
        parsed = zzxxmla1_cl_schema_def=>parse( file-content ).
      CATCH zzxxmla1_cx_xom INTO DATA(xom_error).
        RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 500
          message = |Schema file { entry-definition } not readable: { xom_error->error_message }|.
    ENDTRY.
    DATA(outline) = outline( parsed ).
    " the tables as the schema names them: without views, nothing is replaced
    DATA(numbers) = int_columns( map_tables( CHANGING schema = parsed ) ).
    result = |\{"catalog":{ json( entry-name ) },"dataSource":{ json( entry-data_source ) },| &&
             |"file":{ json( entry-definition ) },"changedAt":{ json_timestamp( file-changed_at ) },| &&
             |"changedBy":{ json( file-changed_by ) },"xml":{ json( file-content ) },"outline":{ outline },| &&
             |"intColumns":{ int_columns_json( numbers ) },{ characteristics_json( parsed ) }\}|.
  ENDMETHOD.

  METHOD check.
    DATA(probed) = xsdbool( to_lower( parameter( request = request name = `probe` ) ) = `true` ).
    DATA(checked) = check_request( request = request probe = probed ).
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
             |"views":{ json_array( characteristics ) }| &&
             |{ COND #( WHEN probed = abap_true THEN |,"probe":{ cubes_json( checked-probed ) }| ) }\}|.
  ENDMETHOD.

  METHOD check_request.
    TRY.
        result-schema = zzxxmla1_cl_schema_def=>parse( request-body ).
      CATCH zzxxmla1_cx_xom INTO DATA(xom_error).
        RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400 message = |Schema not readable: { xom_error->error_message }|.
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
    check_selections( result-schema ).
    IF probe = abap_true.
      result-probed = probe_schema( result-schema ).
    ENDIF.
  ENDMETHOD.

  METHOD accept.
    DATA(checked) = check_request( request = request probe = abap_true ).
    DATA(schema) = checked-schema.
    DATA(catalog) = checked-catalog.
    DATA(path) = checked-path.

    " the selections of the cubes that use each table
    DATA(selections) = table_selections( schema ).

    " nothing is changed before this point
    DATA views TYPE zzxxmla1_cl_bw_view_gen=>ty_t_view.
    DATA(generator) = NEW zzxxmla1_cl_bw_view_gen( ).
    DATA(tables) = map_tables( CHANGING schema = schema ).
    LOOP AT tables INTO DATA(table).
      DATA(characteristic) = characteristic_of( table ).
      IF characteristic IS NOT INITIAL.
        DATA(selection) = VALUE #( selections[ table = table ]-cube OPTIONAL ).
        TRY.
            IF zzxxmla1_cl_bw_view_gen=>provider_of_fact_placeholder( table ) IS NOT INITIAL.
              DATA(fact_view) = generator->generate_fact_view( provider  = CONV #( characteristic )
                                                               selection = selection ).
              IF fact_view IS INITIAL.
                RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400
                  message = |{ characteristic } needs no fact view (no compounded characteristic of an aDSO, | &&
                            |nothing filters the cube): name its fact table, or filter the cube on a characteristic|.
              ENDIF.
              APPEND fact_view TO views.
            ELSE.
              APPEND generator->generate( characteristic = CONV #( characteristic )
                                          selection      = selection ) TO views.
            ENDIF.
          CATCH cx_dd_ddl_exception INTO DATA(ddl_error).
            RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 500
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
    DATA(deleted_views) = delete_unused_views( checked-new_datasources ).

    DATA view_list TYPE string_table.
    LOOP AT views INTO DATA(view).
      APPEND |\{"characteristic":{ json( view-characteristic ) },"ddlName":{ json( view-ddl_name ) },| &&
             |"viewName":{ json( view-view_name ) },"selection":{ json( view-selection ) }\}| TO view_list.
    ENDLOOP.
    " the tables with the views put in, whose numbers the UI switches to
    DATA(accepted_tables) = map_tables( CHANGING schema = schema ).
    result = |\{"catalog":{ json( catalog ) },"file":{ json( path ) },"views":{ json_array( view_list ) },| &&
             |"deletedViews":{ json_array( deleted_views ) },| &&
             |"xml":{ json( xml ) },"intColumns":{ int_columns_json( int_columns( accepted_tables ) ) }\}|.
  ENDMETHOD.

  METHOD remove.
    DATA(catalog) = parameter( request = request name = `catalog` ).
    IF catalog IS INITIAL.
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400 message = `Parameter catalog is missing`.
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
    DATA(deleted_views) = delete_unused_views( new_datasources ).
    result = |\{"catalog":{ json( catalog ) },"removedFiles":{ json_array( removed ) },| &&
             |"deletedViews":{ json_array( deleted_views ) }\}|.
  ENDMETHOD.

  METHOD probe.
    GET RUN TIME FIELD DATA(start).
    DATA(catalog) = parameter( request = request name = `catalog` ).
    DATA(entries) = first_catalogs( datasources_file( )-content ).
    IF catalog IS NOT INITIAL.
      DELETE entries WHERE name <> catalog.
      IF entries IS INITIAL.
        RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 404 message = |No catalog '{ catalog }'|.
      ENDIF.
    ENDIF.
    DATA(prober) = NEW zzxxmla1_cl_schema_probe( ).
    DATA catalogs TYPE string_table.
    LOOP AT entries INTO DATA(entry).
      DATA(error) = ``.
      DATA cubes TYPE zzxxmla1_cl_schema_probe=>ty_t_cube.
      CLEAR cubes.
      DATA(file) = zzxxmla1_cl_files=>read( entry-definition ).
      IF file-path IS INITIAL.
        error = |The schema file { entry-definition } does not exist|.
      ELSE.
        TRY.
            cubes = prober->probe_schema( zzxxmla1_cl_schema_def=>parse( file-content ) ).
          CATCH zzxxmla1_cx_xom INTO DATA(xom_error).
            error = |Schema file { entry-definition } not readable: { xom_error->error_message }|.
          CATCH zzxxmla1_cx_bw_provider zzxxmla1_cx_sql INTO DATA(probe_error).
            error = probe_error->get_text( ).
        ENDTRY.
      ENDIF.
      DATA(ok) = xsdbool( error IS INITIAL AND NOT line_exists( cubes[ ok = abap_false ] ) ).
      APPEND |\{"catalog":{ json( entry-name ) },"ok":{ json_bool( ok ) },| &&
             COND string( WHEN error IS NOT INITIAL THEN |"error":{ json( error ) },| ) &&
             |"cubes":{ cubes_json( cubes ) }\}| TO catalogs.
    ENDLOOP.
    GET RUN TIME FIELD DATA(stop).
    result = |\{"catalogs":{ json_array( catalogs ) },"runtime":{ ( stop - start ) DIV 1000 }\}|.
  ENDMETHOD.

  METHOD probe_schema.
    TRY.
        result = NEW zzxxmla1_cl_schema_probe( )->probe_schema( schema ).
      CATCH zzxxmla1_cx_bw_provider INTO DATA(error).
        RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400 message = error->get_text( ).
    ENDTRY.
    DATA(refusal) = zzxxmla1_cl_schema_probe=>refusal( result ).
    IF refusal IS NOT INITIAL.
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400 message = refusal.
    ENDIF.
  ENDMETHOD.

  METHOD cubes_json.
    DATA entries TYPE string_table.
    LOOP AT cubes INTO DATA(cube).
      DATA characteristics TYPE string_table.
      CLEAR characteristics.
      LOOP AT cube-characteristics INTO DATA(characteristic).
        DATA(values) = VALUE string_table( FOR v IN characteristic-values
                                           ( |\{"value":{ json( v-value ) },"facts":{ v-facts }\}| ) ).
        APPEND |\{"name":{ json( characteristic-name ) },"ok":{ json_bool( characteristic-ok ) },| &&
               |"values":{ json_array( values ) }\}| TO characteristics.
      ENDLOOP.
      APPEND |\{"cube":{ json( cube-cube ) },"ok":{ json_bool( cube-ok ) },| &&
             |"characteristics":{ json_array( characteristics ) }\}| TO entries.
    ENDLOOP.
    result = json_array( entries ).
  ENDMETHOD.

  METHOD time_status.
    DATA(time_md) = NEW zzxxmla1_cl_time_md( ).
    result = |\{{ time_status_json( time_md = time_md interval = time_interval( request ) ) }\}|.
  ENDMETHOD.

  METHOD fill_time.
    DATA(interval) = time_interval( request ).
    DATA names TYPE string_table.
    SPLIT replace( val = parameter( request = request name = `characteristics` ) sub = ` ` with = `` occ = 0 )
      AT `,` INTO TABLE names.
    DELETE names WHERE table_line IS INITIAL.
    DATA(time_md) = NEW zzxxmla1_cl_time_md( ).
    DATA filled TYPE string_table.
    LOOP AT time_md->fill( interval = interval names = names ) INTO DATA(entry).
      APPEND |\{"name":{ json( entry-name ) },"createdSids":{ entry-created_sids },| &&
             |"attributeRows":{ entry-attribute_rows },| &&
             |"error":{ COND string( WHEN entry-error IS INITIAL THEN `null` ELSE json( entry-error ) ) }\}| TO filled.
    ENDLOOP.
    result = |\{"filled":{ json_array( filled ) },{ time_status_json( time_md = time_md interval = interval ) }\}|.
  ENDMETHOD.

  METHOD trace_status.
    DATA(filter) = user_parameter( request = request name = `filter` ).
    DATA users TYPE string_table.
    LOOP AT zzxxmla1_cl_trace=>users( ) INTO DATA(user).
      APPEND |\{"user":{ json( |{ user-user_name }| ) },"since":{ json_timestamp( user-changed_at ) },| &&
             |"by":{ json( |{ user-changed_by }| ) },"until":{ json_timestamp( user-active_until ) }\}| TO users.
    ENDLOOP.
    DATA calls TYPE string_table.
    LOOP AT zzxxmla1_cl_trace=>list( user_name = filter ) INTO DATA(entry).
      APPEND |\{{ trace_entry_json( entry ) }\}| TO calls.
    ENDLOOP.
    result = |\{"user":{ json( |{ sy-uname }| ) },"retentionDays":{ zzxxmla1_cl_trace=>c_retention_days },| &&
             |"activeHours":{ zzxxmla1_cl_trace=>c_active_hours },| &&
             |"users":{ json_array( users ) },"calls":{ json_array( calls ) }\}|.
  ENDMETHOD.

  METHOD trace_entry.
    DATA(call) = traced_call( request ).
    DATA(truncated) = xsdbool( strlen( call-response ) > c_trace_shown ).
    DATA(shown) = COND string( WHEN truncated = abap_true THEN substring( val = call-response len = c_trace_shown )
                               ELSE call-response ).
    result = |\{{ trace_entry_json( call-entry ) },"request":{ json( call-request ) },| &&
             |"response":{ json( shown ) },"responseTruncated":{ json_bool( truncated ) }\}|.
  ENDMETHOD.

  METHOD trace_response.
    result = traced_call( request )-response.
  ENDMETHOD.

  METHOD switch_trace.
    CASE resource.
      WHEN `trace/on`.
        zzxxmla1_cl_trace=>activate( user_parameter( request = request name = `user` fallback = sy-uname ) ).
      WHEN `trace/off`.
        zzxxmla1_cl_trace=>deactivate( user_parameter( request = request name = `user` fallback = sy-uname ) ).
      WHEN OTHERS.
        zzxxmla1_cl_trace=>clear( user_name = user_parameter( request = request name = `user` ) ).
    ENDCASE.
    COMMIT WORK.
    result = trace_status( request ).
  ENDMETHOD.

  METHOD user_parameter.
    DATA(text) = to_upper( condense( parameter( request = request name = name ) ) ).
    IF text IS INITIAL.
      result = fallback.
      RETURN.
    ENDIF.
    IF strlen( text ) > 12 OR text CA ` *`.
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused
        EXPORTING status  = 400
                  message = |{ name } is not a user name: { text }|.
    ENDIF.
    result = text.
  ENDMETHOD.

  METHOD traced_call.
    DATA(id) = to_upper( condense( parameter( request = request name = `id` ) ) ).
    IF id IS INITIAL.
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused
        EXPORTING status  = 400
                  message = `id is missing`.
    ENDIF.
    IF strlen( id ) <= 32.
      result = zzxxmla1_cl_trace=>read( CONV #( id ) ).
    ENDIF.
    IF result-entry-trace_id IS INITIAL.
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused
        EXPORTING status  = 404
                  message = |No traced call { id }|.
    ENDIF.
  ENDMETHOD.

  METHOD trace_entry_json.
    result = |"id":{ json( |{ entry-trace_id }| ) },"user":{ json( |{ entry-user_name }| ) },| &&
             |"at":{ json_timestamp( entry-created_at ) },"method":{ json( entry-xmla_method ) },| &&
             |"type":{ json( entry-request_type ) },"mdx":{ json( entry-mdx ) },"status":{ entry-status },| &&
             |"fault":{ json_bool( entry-fault ) },"runtimeMs":{ entry-runtime_ms },| &&
             |"client":{ json( entry-client_address ) },"userAgent":{ json( entry-user_agent ) },| &&
             |"requestLength":{ entry-request_length },"responseLength":{ entry-response_length }|.
  ENDMETHOD.

  METHOD time_interval.
    result = NEW zzxxmla1_cl_time_md( )->interval( ).
    DATA(from) = date_parameter( request = request name = `from` ).
    DATA(to) = date_parameter( request = request name = `to` ).
    IF from IS NOT INITIAL.
      result-from = from.
    ENDIF.
    IF to IS NOT INITIAL.
      result-to = to.
    ENDIF.
    IF result-from > result-to.
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused
        EXPORTING status  = 400
                  message = |The interval starts after it ends: { json_date( result-from ) } to { json_date( result-to ) }|.
    ENDIF.
    IF result-to - result-from > 36525.
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused
        EXPORTING status  = 400
                  message = `The interval is longer than 100 years`.
    ENDIF.
  ENDMETHOD.

  METHOD date_parameter.
    DATA(text) = replace( val = parameter( request = request name = name ) sub = `-` with = `` occ = 0 ).
    IF text IS INITIAL.
      RETURN.
    ENDIF.
    IF strlen( text ) = 8 AND text CO `0123456789`.
      result = text.
    ENDIF.
    " an impossible date (20260231) is 0 as a number
    IF result IS INITIAL OR result(4) < `1000` OR CONV d( CONV i( result ) ) <> result.
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused
        EXPORTING status  = 400
                  message = |{ name } is not a date (YYYY-MM-DD): { parameter( request = request name = name ) }|.
    ENDIF.
  ENDMETHOD.

  METHOD time_status_json.
    DATA entries TYPE string_table.
    LOOP AT time_md->status( interval ) INTO DATA(entry).
      APPEND |\{"name":{ json( entry-characteristic-name ) },"sidTable":{ json( entry-characteristic-sid_table ) },| &&
             |"attributeTable":{ COND string( WHEN entry-characteristic-attribute_table IS INITIAL THEN `null`
                                               ELSE json( entry-characteristic-attribute_table ) ) },| &&
             |"sids":{ entry-sids },"attributes":{ entry-attributes },"expected":{ entry-expected },| &&
             |"missingSids":{ entry-missing_sids },"missingAttributes":{ entry-missing_attributes },| &&
             |"first":{ json( entry-first ) },"last":{ json( entry-last ) }\}| TO entries.
    ENDLOOP.
    result = |"from":{ json_date( interval-from ) },"to":{ json_date( interval-to ) },| &&
             |"calendar":{ json( interval-calendar ) },"characteristics":{ json_array( entries ) }|.
  ENDMETHOD.

  METHOD json_date.
    result = |"{ value(4) }-{ value+4(2) }-{ value+6(2) }"|.
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
        RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 500 message = error->description.
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
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 500 message = |The server has no { zzxxmla1_cl_files=>c_datasources }|.
    ENDIF.
  ENDMETHOD.

  METHOD check_catalog_name.
    IF NOT matches( val = catalog regex = `[A-Za-z0-9_][A-Za-z0-9_.\-]*` ).
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400
        message = |Catalog name '{ catalog }': only letters, digits, _, - and . (not first) are allowed|.
    ENDIF.
  ENDMETHOD.

  METHOD add_catalog.
    DATA data_sources TYPE zzxxmla1_cl_repository=>ty_t_data_source.
    TRY.
        data_sources = zzxxmla1_cl_repository=>of_content( content )->data_sources( ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 500 message = error->description.
    ENDTRY.
    IF data_sources IS INITIAL.
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 500
        message = |{ zzxxmla1_cl_files=>c_datasources } has no data source|.
    ENDIF.
    DATA(registered) = abap_false.
    LOOP AT data_sources INTO DATA(data_source).
      LOOP AT data_source-catalogs INTO DATA(existing) WHERE name = catalog.
        IF existing-definition <> definition.
          RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400
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
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 500
        message = |The catalog cannot be added to the Catalogs of the first data source of { zzxxmla1_cl_files=>c_datasources }|.
    ENDIF.
  ENDMETHOD.

  METHOD remove_catalog.
    DATA(before) = all_catalogs( content ).
    DATA(expected) = before.
    DELETE expected WHERE name = catalog.
    IF lines( expected ) = lines( before ).
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 404 message = |No catalog '{ catalog }'|.
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
      CATCH zzxxmla1_cx_api_refused.
        removed = abap_false.
    ENDTRY.
    IF removed = abap_false.
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 500
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
          RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 500
            message = |Catalog '{ entry-name }': the schema file { entry-definition } does not exist|.
        ENDIF.
        APPEND VALUE #( name = entry-name schema = file-content updated_at = file-changed_at ) TO catalogs.
      ENDIF.
    ENDLOOP.
    TRY.
        zzxxmla1_cl_schema=>of_catalogs( catalogs ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400 message = error->description.
    ENDTRY.
  ENDMETHOD.

  METHOD map_tables.
    LOOP AT schema-dimensions ASSIGNING FIELD-SYMBOL(<dimension>).
      map_dimension( EXPORTING views = views CHANGING dimension = <dimension> names = result ).
    ENDLOOP.
    LOOP AT schema-cubes INTO DATA(cube).
      IF cube-fact-name = `Table`.
        " the node refers to the table, so it changes in the schema
        DATA(fact) = CAST zzxxmla1_cl_schema_def=>ty_table( cube-fact-def ).
        map_table( EXPORTING views = views CHANGING table = fact->name names = result ).
      ENDIF.
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
    DATA(characteristic) = characteristic_of( table ).
    IF characteristic IS INITIAL.
      RETURN.
    ENDIF.
    DATA(kind) = COND #( WHEN zzxxmla1_cl_bw_view_gen=>provider_of_fact_placeholder( table ) IS NOT INITIAL
                         THEN zzxxmla1_cl_bw_view_gen=>c_kind-fact
                         ELSE zzxxmla1_cl_bw_view_gen=>c_kind-characteristic ).
    READ TABLE views INTO DATA(view) WITH KEY kind = kind characteristic = CONV rsiobjnm( characteristic ).
    IF sy-subrc = 0.
      table = view-view_name.
    ENDIF.
  ENDMETHOD.

  METHOD table_selections.
    DATA(registered) = NEW zzxxmla1_cl_bw_view_gen( )->registered( ).
    DATA used TYPE string_table.
    LOOP AT schema-cubes INTO DATA(cube).
      DATA(selection) = cube_selection( cube ).
      IF cube-fact-name = `Table`.
        DATA(fact) = CAST zzxxmla1_cl_schema_def=>ty_table( cube-fact-def ).
        " the facts of a cube that filters on characteristics are filtered by its fact view only
        IF zzxxmla1_cl_bw_view_gen=>filter_selection( selection ) IS NOT INITIAL
            AND zzxxmla1_cl_bw_view_gen=>provider_of_fact_placeholder( fact->name ) IS INITIAL
            AND NOT line_exists( registered[ kind      = zzxxmla1_cl_bw_view_gen=>c_kind-fact
                                             view_name = CONV viewname( fact->name ) ] ).
          RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400
            message = |Cube '{ cube-name }' filters on characteristics, so its facts must be its fact view, not | &&
                      |{ fact->name }: restrict them on a dimension's pane (the annotations alone do not filter)|.
        ENDIF.
        add_table_selection( EXPORTING table = fact->name selection = selection registered = registered
                             CHANGING  selections = result ).
      ENDIF.
      LOOP AT cube-dimensions INTO DATA(node).
        DATA dimension TYPE zzxxmla1_cl_schema_def=>ty_dimension.
        CLEAR dimension.
        IF node-name = `Dimension`.
          DATA(own) = CAST zzxxmla1_cl_schema_def=>ty_dimension( node-def ).
          dimension = own->*.
        ELSEIF node-name = `DimensionUsage`.
          DATA(usage) = CAST zzxxmla1_cl_schema_def=>ty_dimension_usage( node-def ).
          READ TABLE schema-dimensions INTO dimension WITH KEY name = usage->source.
          IF sy-subrc = 0.
            APPEND usage->source TO used.
          ENDIF.
        ENDIF.
        IF dimension IS INITIAL.
          CONTINUE.
        ENDIF.
        DATA(tables) = VALUE string_table( ( dimension-table ) ).
        LOOP AT dimension-hierarchies INTO DATA(hierarchy) WHERE relation-name = `Table`.
          DATA(relation) = CAST zzxxmla1_cl_schema_def=>ty_table( hierarchy-relation-def ).
          APPEND relation->name TO tables.
        ENDLOOP.
        LOOP AT tables INTO DATA(table) WHERE table_line IS NOT INITIAL.
          add_table_selection( EXPORTING table = table selection = selection registered = registered
                               CHANGING  selections = result ).
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.
    " a shared dimension no cube uses: the plain view
    LOOP AT schema-dimensions INTO DATA(shared) WHERE table IS NOT INITIAL.
      IF NOT line_exists( used[ table_line = shared-name ] ).
        add_table_selection( EXPORTING table = shared-table selection = VALUE #( ) registered = registered
                             CHANGING  selections = result ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD add_table_selection.
    DATA entry TYPE ty_table_selection.
    entry-table = table.
    entry-cube = selection.
    " whose view the table is: a placeholder's, or one of table ZZXXMLA1_VIEW
    DATA(provider) = zzxxmla1_cl_bw_view_gen=>provider_of_fact_placeholder( table ).
    DATA(characteristic) = zzxxmla1_cl_bw_view_gen=>characteristic_of_placeholder( table ).
    IF provider IS NOT INITIAL.
      entry-kind = zzxxmla1_cl_bw_view_gen=>c_kind-fact.
      entry-object = provider.
    ELSEIF characteristic IS NOT INITIAL.
      entry-kind = zzxxmla1_cl_bw_view_gen=>c_kind-characteristic.
      entry-object = characteristic.
    ELSE.
      READ TABLE registered INTO DATA(view) WITH KEY view_name = CONV viewname( table ).
      IF sy-subrc <> 0.
        RETURN.
      ENDIF.
      entry-kind = view-kind.
      entry-object = view-characteristic.
    ENDIF.
    IF entry-kind = zzxxmla1_cl_bw_view_gen=>c_kind-fact.
      entry-selection = zzxxmla1_cl_bw_selection=>selection_text(
                          zzxxmla1_cl_bw_view_gen=>filter_selection( selection ) ).
    ELSE.
      entry-selection = zzxxmla1_cl_bw_selection=>selection_text(
        NEW zzxxmla1_cl_bw_view_gen( )->view_selection( characteristic = CONV #( entry-object )
                                                        selection      = selection ) ).
    ENDIF.
    READ TABLE selections INTO DATA(other) WITH KEY table = table.
    IF sy-subrc <> 0.
      APPEND entry TO selections.
    ELSEIF other-selection <> entry-selection.
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400
        message = |{ table } is used by cubes with different selections of it | &&
                  |({ COND #( WHEN other-selection IS INITIAL THEN `none` ELSE other-selection ) } and | &&
                  |{ COND #( WHEN entry-selection IS INITIAL THEN `none` ELSE entry-selection ) }): | &&
                  |give each cube a schema of its own|.
    ENDIF.
  ENDMETHOD.

  METHOD check_selections.
    DATA(registered) = NEW zzxxmla1_cl_bw_view_gen( )->registered( ).
    LOOP AT table_selections( schema ) INTO DATA(entry).
      READ TABLE registered INTO DATA(view) WITH KEY view_name = CONV viewname( entry-table ).
      IF sy-subrc = 0 AND view-selection <> entry-selection.
        RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400
          message = |{ entry-table } is the view of { view-characteristic } for | &&
                    |{ COND #( WHEN view-selection IS INITIAL THEN `no selection` ELSE view-selection ) }, | &&
                    |but its cube restricts { COND #( WHEN entry-selection IS INITIAL THEN `nothing of it`
                                                      ELSE entry-selection ) }: restrict the characteristics on a | &&
                    |dimension's pane (the annotations alone do not change the tables)|.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD delete_unused_views.
    " the tables every catalog's schema names; a schema that cannot be read could name any view, so none is deleted
    DATA used TYPE string_table.
    TRY.
        LOOP AT all_catalogs( datasources ) INTO DATA(entry).
          DATA(file) = zzxxmla1_cl_files=>read( entry-definition ).
          IF file-path IS INITIAL.
            CONTINUE.
          ENDIF.
          DATA(schema) = zzxxmla1_cl_schema_def=>parse( file-content ).
          APPEND LINES OF map_tables( CHANGING schema = schema ) TO used.
        ENDLOOP.
        LOOP AT NEW zzxxmla1_cl_bw_view_gen( )->delete_unused( used ) INTO DATA(view).
          APPEND json( view-view_name ) TO result.
        ENDLOOP.
        COMMIT WORK.
      CATCH zzxxmla1_cx_api_refused zzxxmla1_cx_xom cx_dd_ddl_exception.
        ROLLBACK WORK.
        CLEAR result.
    ENDTRY.
  ENDMETHOD.

  METHOD characteristic_of.
    result = zzxxmla1_cl_bw_view_gen=>characteristic_of_placeholder( table ).
    IF result IS INITIAL.
      result = zzxxmla1_cl_bw_view_gen=>provider_of_fact_placeholder( table ).
    ENDIF.
  ENDMETHOD.

  METHOD int_columns.
    IF tables IS INITIAL.
      RETURN.
    ENDIF.
    DATA names TYPE RANGE OF tabname.
    names = VALUE #( FOR t IN tables ( sign = 'I' option = 'EQ' low = t ) ).
    SELECT tabname, fieldname, datatype, leng FROM dd03l
      WHERE tabname IN @names AND as4local = 'A'
      INTO TABLE @DATA(fields).
    LOOP AT tables INTO DATA(table).
      LOOP AT fields INTO DATA(field) WHERE tabname = table.
        READ TABLE fields INTO DATA(number) WITH KEY tabname = table fieldname = |{ field-fieldname }_INT|.
        IF sy-subrc = 0.
          APPEND VALUE #( table      = table
                          column     = field-fieldname
                          int_column = number-fieldname
                          data_type  = zzxxmla1_cl_schema_proposal=>data_type(
                                         VALUE #( datatype = number-datatype length = number-leng ) ) ) TO result.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD int_columns_json.
    DATA entries TYPE string_table.
    LOOP AT int_columns INTO DATA(entry).
      APPEND |\{"table":{ json( entry-table ) },"column":{ json( entry-column ) },| &&
             |"intColumn":{ json( entry-int_column ) },"dataType":{ json( entry-data_type ) }\}| TO entries.
    ENDLOOP.
    result = json_array( entries ).
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
