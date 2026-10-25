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
"! The endpoint for BW's MDX on InfoProviders below the ICF node, /bw/ (docs/next-steps.md, Next: BW's MDX on
"! InfoProviders). It answers with the authorisation result of a user, never with data, so the user is a parameter:
"! - POST check[?user=U][&keyDate=YYYY-MM-DD][&sql=true]: the body is a statement of BW's MDX (FROM [$ZCLVISITA]), plain or as an
"!   XMLA Execute; U a test user of the scenarios (ZZXXMLA1_CL_BW_AUTH_GEN) or the caller (default; refused, 403, for
"!   any other user, as GET auth/check of the schema API), the key date 9999-12-31 by default. The statement is parsed
"!   and resolved in BW's names (ZZXXMLA1_CL_MDX_SCHEMA_READER=>for_bw_cube), its slicer, axes and subselects
"!   evaluated without cells (ZZXXMLA1_CL_MDX_ENGINE=>members), and their selection (ZZXXMLA1_CL_BW_AUTH_SELECTION)
"!   checked for the user at the key date in HANA (ZZXXMLA1_CL_BW_AUTH_SQL, phase Authorisation). The answer is the
"!   user, key date, the status as the probe classifies BW's (OK, EMPTY: allowed but an axis has no tuple, NO AUTH,
"!   UNKNOWN: a value the user may not see at all, ERROR: the fault's text as message), the check's reason and BW's
"!   message, the statement in olap4abap's names and the selection; with sql=true also the SQL statements the check
"!   ran (sql: text, rows, microseconds, error, phase). Nothing is enforced: the members of a hierarchy are not yet
"!   restricted to what the user may see (docs/next-steps.md, the authorisations' step 5b).
"! ZZXXMLA1_MAIN_ENDPOINT traces a check as it traces an XMLA call (ZZXXMLA1_CL_TRACE, described by describe).
CLASS zzxxmla1_cl_bw_mdx_api DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! the path of the endpoint below the ICF node
    CONSTANTS c_path TYPE string VALUE `/bw/`.
    TYPES:
      BEGIN OF ty_parameter,
        name  TYPE string,
        value TYPE string,
      END OF ty_parameter,
      ty_t_parameter TYPE STANDARD TABLE OF ty_parameter WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_request,
        method     TYPE string,          " GET, POST, ...
        path       TYPE string,          " below the ICF node: /bw/check
        parameters TYPE ty_t_parameter,  " of the query string, names in lower case
        body       TYPE string,
      END OF ty_request.
    TYPES:
      BEGIN OF ty_result,
        status       TYPE i,
        content_type TYPE string,
        body         TYPE string,
        allow        TYPE string,  " the methods of the resource, for 405
        failed       TYPE abap_bool,  " the check's status is ERROR (a fault in the trace)
      END OF ty_result.

    "! Whether the path (below the ICF node) is one of this endpoint: /bw and below.
    CLASS-METHODS is_api
      IMPORTING !path         TYPE string
      RETURNING VALUE(result) TYPE abap_bool.
    METHODS handle
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE ty_result.
    "! What a request asks, for its trace: method CHECK, the user and key date checked (as given, the defaults if
    "! not), the statement (the body if it has none).
    CLASS-METHODS describe
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE zzxxmla1_cl_trace=>ty_call.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CONSTANTS c_json TYPE string VALUE `application/json; charset=utf-8`.
    "! the key date without parameter
    CONSTANTS c_key_date TYPE d VALUE '99991231'.

    "! POST check: the statement resolved in BW's names for the user at the key date.
    METHODS check
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE ty_result
      RAISING   zzxxmla1_cx_api_refused.
    "! The statements logged from the index first on (ZZXXMLA1_CL_SQL=>statement_log) as a JSON array.
    CLASS-METHODS logged_json
      IMPORTING !first        TYPE i
      RETURNING VALUE(result) TYPE string.
    "! The MDX statement of a body: an XMLA Execute's (a body starting with <), else the body.
    CLASS-METHODS statement_of
      IMPORTING body          TYPE string
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_xmla.
    "! the tuples of a factor the answer lists
    CONSTANTS c_max_tuples TYPE i VALUE 100.
    "! The members of a statement in BW's names (ZZXXMLA1_CL_MDX_ENGINE=>members, no cells); a fault of the parser,
    "! validator or engine if it has none.
    CLASS-METHODS members_of
      IMPORTING statement     TYPE string
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_engine=>ty_members
      RAISING   zzxxmla1_cx_xmla.
    "! The selection as JSON: per factor its name, number of tuples and the first c_max_tuples, the named members.
    CLASS-METHODS selection_json
      IMPORTING selection     TYPE zzxxmla1_cl_bw_auth_selection=>ty_selection
      RETURNING VALUE(result) TYPE string.
    CLASS-METHODS parameter
      IMPORTING request       TYPE ty_request
                !name         TYPE string
      RETURNING VALUE(result) TYPE string.
    "! A user name parameter, upper case; the fallback if it is missing; refused (400) if it is no user name.
    CLASS-METHODS user_parameter
      IMPORTING request       TYPE ty_request
                !name         TYPE string
                fallback      TYPE xubname
      RETURNING VALUE(result) TYPE xubname
      RAISING   zzxxmla1_cx_api_refused.
    "! A date YYYY-MM-DD (or YYYYMMDD); refused (400) if it is none.
    CLASS-METHODS date_of
      IMPORTING !text         TYPE string
                !name         TYPE string
      RETURNING VALUE(result) TYPE d
      RAISING   zzxxmla1_cx_api_refused.
    CLASS-METHODS json
      IMPORTING !value        TYPE string
      RETURNING VALUE(result) TYPE string.
    CLASS-METHODS error_result
      IMPORTING !status       TYPE i
                !message      TYPE string
      RETURNING VALUE(result) TYPE ty_result.
ENDCLASS.



CLASS zzxxmla1_cl_bw_mdx_api IMPLEMENTATION.

  METHOD is_api.
    result = xsdbool( path = `/bw` OR ( strlen( path ) >= strlen( c_path )
                                        AND substring( val = path len = strlen( c_path ) ) = c_path ) ).
  ENDMETHOD.

  METHOD handle.
    DATA(resource) = COND string( WHEN strlen( request-path ) > strlen( c_path )
                                  THEN substring( val = request-path off = strlen( c_path ) ) ).
    IF resource <> `check`.
      result = error_result( status = 404 message = |No resource { request-path }| ).
      RETURN.
    ENDIF.
    IF request-method <> `POST`.
      result = error_result( status = 405 message = |{ request-method } is not allowed on { resource }| ).
      result-allow = `POST`.
      RETURN.
    ENDIF.
    TRY.
        result = check( request ).
      CATCH zzxxmla1_cx_api_refused INTO DATA(refused).
        result = error_result( status = refused->status message = refused->message ).
      CATCH cx_root INTO DATA(error) ##CATCH_ALL.
        " a JSON error rather than a dump the caller cannot read
        result = error_result( status = 500 message = error->get_text( ) ).
    ENDTRY.
  ENDMETHOD.

  METHOD check.
    DATA(key_date) = c_key_date.
    DATA(date_text) = parameter( request = request name = `keydate` ).
    IF date_text IS NOT INITIAL.
      key_date = date_of( text = date_text name = `keyDate` ).
    ENDIF.
    DATA(user) = user_parameter( request = request name = `user` fallback = sy-uname ).
    DATA(scenarios) = zzxxmla1_cl_bw_auth_gen=>scenarios( ).
    IF user <> sy-uname AND NOT line_exists( scenarios[ user = user ] ).
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused
        EXPORTING status  = 403
                  message = |The check runs for a test user of the scenarios only, not for { user }|.
    ENDIF.
    IF condense( request-body ) = ``.
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused EXPORTING status = 400 message = `The statement is missing`.
    ENDIF.

    " sql=true: the statements are logged while the check runs (they are already while the call is traced)
    DATA(with_sql) = xsdbool( to_lower( parameter( request = request name = `sql` ) ) = `true` ).
    DATA(was_logging) = zzxxmla1_cl_sql=>log_statements.
    IF with_sql = abap_true.
      zzxxmla1_cl_sql=>log_statements = abap_true.
    ENDIF.
    DATA(first_logged) = lines( zzxxmla1_cl_sql=>statement_log ) + 1.
    DATA(phase) = zzxxmla1_cl_sql=>log_phase.

    DATA(status) = `ERROR`.
    DATA(reason) = ``.
    DATA(message) = ``.
    DATA(statement) = ``.
    DATA(resolved) = ``.
    DATA selection TYPE zzxxmla1_cl_bw_auth_selection=>ty_selection.
    TRY.
        statement = statement_of( request-body ).
        zzxxmla1_cl_sql=>log_phase = `Resolve`.
        DATA(members) = members_of( statement ).
        resolved = zzxxmla1_cl_mdx_parser=>to_mdx( VALUE #( kind = `SELECT` query = members-query ) ).
        selection = zzxxmla1_cl_bw_auth_selection=>of_members( members ).
        zzxxmla1_cl_sql=>log_phase = `Authorisation`.
        zzxxmla1_cl_sql=>log_node = 0.
        DATA(provider) = to_upper( substring( val = members-query-cube off = 1 ) ).
        DATA(checked) = zzxxmla1_cl_bw_auth_sql=>read( user = user provider = provider key_date = key_date
                                                     )->check_query( factors = selection-factors
                                                                     members = selection-named ).
        status = COND #( WHEN checked-status <> zzxxmla1_cl_bw_auth=>c_status-allowed THEN condense( checked-status )
                         WHEN selection-empty = abap_true THEN `EMPTY`
                         ELSE `OK` ).
        reason = condense( checked-reason ).
        message = checked-message.
      CATCH zzxxmla1_cx_xmla INTO DATA(fault).
        message = fault->description.
      CATCH zzxxmla1_cx_bw_provider zzxxmla1_cx_bw_hierarchy zzxxmla1_cx_sql INTO DATA(error).
        message = error->get_text( ).
    ENDTRY.
    zzxxmla1_cl_sql=>log_phase = phase.
    zzxxmla1_cl_sql=>log_statements = was_logging.

    DATA(body) = |\{"user":{ json( |{ user }| ) },"keyDate":{ json( |{ key_date DATE = ISO }| ) },| &&
                 |"status":{ json( status ) },"reason":{ json( reason ) },"message":{ json( message ) },| &&
                 |"statement":{ json( statement ) },"resolved":{ json( resolved ) },| &&
                 |"selection":{ selection_json( selection ) }|.
    IF with_sql = abap_true.
      body = |{ body },"sql":{ logged_json( first_logged ) }|.
    ENDIF.
    result = VALUE #( status = 200 content_type = c_json body = |{ body }\}| failed = xsdbool( status = `ERROR` ) ).
  ENDMETHOD.

  METHOD describe.
    DATA(user) = to_upper( condense( parameter( request = request name = `user` ) ) ).
    DATA(key_date) = condense( parameter( request = request name = `keydate` ) ).
    TRY.
        DATA(statement) = statement_of( request-body ).
      CATCH zzxxmla1_cx_xmla.
        statement = request-body.
    ENDTRY.
    result = VALUE #( xmla_method  = `CHECK`
                      request_type = |{ COND #( WHEN user IS INITIAL THEN CONV string( sy-uname ) ELSE user ) } | &&
                                     |{ COND #( WHEN key_date IS INITIAL THEN |{ c_key_date DATE = ISO }| ELSE key_date ) }|
                      mdx          = statement ).
  ENDMETHOD.

  METHOD logged_json.
    DATA statements TYPE string_table.
    LOOP AT zzxxmla1_cl_sql=>statement_log INTO DATA(logged) FROM first.
      APPEND |\{"sql":{ json( logged-sql ) },"rows":{ logged-rows },"us":{ logged-time },| &&
             |"error":{ json( logged-error ) },"phase":{ json( logged-phase ) }\}| TO statements.
    ENDLOOP.
    result = |[{ concat_lines_of( table = statements sep = `,` ) }]|.
  ENDMETHOD.

  METHOD statement_of.
    DATA(text) = condense( translate( val = body from = |\t\n\r| to = `   ` ) ).
    IF strlen( text ) > 0 AND text(1) = `<`.
      DATA(request) = zzxxmla1_cl_xmla_request=>parse( body ).
      IF request-method <> `EXECUTE`.
        zzxxmla1_cx_xmla=>raise_code( kind = `Client` code = `00HSBB01` text = `XMLA SOAP Body processing error`
                                      description = |The body is an XMLA { request-method }, not an Execute| ).
      ENDIF.
      result = request-statement.
    ELSE.
      result = body.
    ENDIF.
  ENDMETHOD.

  METHOD members_of.
    DATA(parsed) = zzxxmla1_cl_mdx_parser=>parse( statement ).
    IF parsed-kind <> `SELECT`.
      zzxxmla1_cx_xmla=>raise_code( kind = `Server` code = `00HSBB01` text = `XMLA SOAP Body processing error`
                                    description = |olap4abap Error:{ parsed-kind } statements are not supported| ).
    ENDIF.
    result = NEW zzxxmla1_cl_mdx_engine( catalog = `` bw_names = abap_true )->members( parsed-query ).
  ENDMETHOD.

  METHOD selection_json.
    DATA factors TYPE string_table.
    LOOP AT selection-factors INTO DATA(factor).
      DATA(index) = sy-tabix.
      DATA(tuples) = VALUE string_table( ).
      LOOP AT factor INTO DATA(tuple) TO c_max_tuples.
        APPEND |[{ concat_lines_of( table = VALUE string_table(
                     FOR m IN tuple ( json( zzxxmla1_cl_bw_auth_selection=>member_text( m ) ) ) ) sep = `,` ) }]|
          TO tuples.
      ENDLOOP.
      APPEND |\{"name":{ json( selection-names[ index ] ) },"count":{ lines( factor ) },| &&
             |"tuples":[{ concat_lines_of( table = tuples sep = `,` ) }]\}| TO factors.
    ENDLOOP.
    DATA(named) = VALUE string_table( FOR n IN selection-named
                                      ( json( zzxxmla1_cl_bw_auth_selection=>member_text( n ) ) ) ).
    result = |\{"factors":[{ concat_lines_of( table = factors sep = `,` ) }],| &&
             |"named":[{ concat_lines_of( table = named sep = `,` ) }]\}|.
  ENDMETHOD.

  METHOD parameter.
    READ TABLE request-parameters INTO DATA(found) WITH KEY name = name.
    IF sy-subrc = 0.
      result = found-value.
    ENDIF.
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

  METHOD date_of.
    DATA(digits) = replace( val = text sub = `-` with = `` occ = 0 ).
    IF strlen( digits ) = 8 AND digits CO `0123456789`.
      result = digits.
    ENDIF.
    " an impossible date (20260231) is 0 as a number
    IF result IS INITIAL OR result(4) < `1000` OR CONV d( CONV i( result ) ) <> result.
      RAISE EXCEPTION TYPE zzxxmla1_cx_api_refused
        EXPORTING status  = 400
                  message = |{ name } is not a date (YYYY-MM-DD): { text }|.
    ENDIF.
  ENDMETHOD.

  METHOD json.
    result = |"{ escape( val = value format = cl_abap_format=>e_json_string ) }"|.
  ENDMETHOD.

  METHOD error_result.
    result = VALUE #( status = status content_type = c_json body = |\{"error":{ json( message ) }\}| ).
  ENDMETHOD.

ENDCLASS.
