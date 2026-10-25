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
"! - POST check[?user=U][&keyDate=YYYY-MM-DD]: the body is a statement of BW's MDX (FROM [$ZCLVISITA]), plain or as an
"!   XMLA Execute; U a test user of the scenarios (ZZXXMLA1_CL_BW_AUTH_GEN) or the caller (default; refused, 403, for
"!   any other user, as GET auth/check of the schema API), the key date 9999-12-31 by default. The statement is parsed
"!   and resolved in BW's names (ZZXXMLA1_CL_MDX_SCHEMA_READER=>for_bw_cube); the answer is the user, key date, the
"!   status (RESOLVED, or ERROR with the fault's text as message) and the statement in olap4abap's names. The check of
"!   the query's selection comes with step 3.
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
      END OF ty_result.

    "! Whether the path (below the ICF node) is one of this endpoint: /bw and below.
    CLASS-METHODS is_api
      IMPORTING !path         TYPE string
      RETURNING VALUE(result) TYPE abap_bool.
    METHODS handle
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE ty_result.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CONSTANTS c_json TYPE string VALUE `application/json; charset=utf-8`.

    "! POST check: the statement resolved in BW's names for the user at the key date.
    METHODS check
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_api_refused.
    "! The MDX statement of a body: an XMLA Execute's (a body starting with <), else the body.
    CLASS-METHODS statement_of
      IMPORTING body          TYPE string
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_xmla.
    "! The statement resolved in BW's names, as MDX in olap4abap's names; a fault of the parser or validator if it
    "! is none.
    CLASS-METHODS resolve
      IMPORTING statement     TYPE string
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_xmla.
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
        result = VALUE #( status = 200 content_type = c_json body = check( request ) ).
      CATCH zzxxmla1_cx_api_refused INTO DATA(refused).
        result = error_result( status = refused->status message = refused->message ).
      CATCH cx_root INTO DATA(error) ##CATCH_ALL.
        " a JSON error rather than a dump the caller cannot read
        result = error_result( status = 500 message = error->get_text( ) ).
    ENDTRY.
  ENDMETHOD.

  METHOD check.
    DATA(key_date) = CONV d( '99991231' ).
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

    DATA(status) = `RESOLVED`.
    DATA(message) = ``.
    DATA(statement) = ``.
    DATA(resolved) = ``.
    TRY.
        statement = statement_of( request-body ).
        resolved = resolve( statement ).
      CATCH zzxxmla1_cx_xmla INTO DATA(fault).
        status = `ERROR`.
        message = fault->description.
    ENDTRY.
    result = |\{"user":{ json( |{ user }| ) },"keyDate":{ json( |{ key_date DATE = ISO }| ) },| &&
             |"status":{ json( status ) },"message":{ json( message ) },| &&
             |"statement":{ json( statement ) },"resolved":{ json( resolved ) }\}|.
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

  METHOD resolve.
    DATA(parsed) = zzxxmla1_cl_mdx_parser=>parse( statement ).
    IF parsed-kind <> `SELECT`.
      zzxxmla1_cx_xmla=>raise_code( kind = `Server` code = `00HSBB01` text = `XMLA SOAP Body processing error`
                                    description = |olap4abap Error:{ parsed-kind } statements are not supported| ).
    ENDIF.
    DATA(query) = parsed-query.
    DATA(reader) = zzxxmla1_cl_mdx_schema_reader=>for_bw_cube( query-cube ).
    NEW zzxxmla1_cl_mdx_validator( reader )->resolve_query( CHANGING query = query ).
    result = zzxxmla1_cl_mdx_parser=>to_mdx( VALUE #( kind = `SELECT` query = query ) ).
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
