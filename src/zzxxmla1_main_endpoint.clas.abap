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
CLASS zzxxmla1_main_endpoint DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_http_extension.
  PROTECTED SECTION.
  PRIVATE SECTION.
    METHODS get_description_html
      RETURNING VALUE(result) TYPE string.
    "! Moves a request of the schema generator's API between HTTP and ZZXXMLA1_CL_SCHEMA_API.
    METHODS handle_schema_api
      IMPORTING server TYPE REF TO if_http_server
                !path  TYPE string.
    "! Moves a request for the schema generator's app (its files) between HTTP and ZZXXMLA1_CL_WEB_APP.
    METHODS handle_web_app
      IMPORTING server TYPE REF TO if_http_server
                !path  TYPE string.
    "! The URL the client used to reach this endpoint, without query string.
    METHODS get_endpoint_url
      IMPORTING server        TYPE REF TO if_http_server
      RETURNING VALUE(result) TYPE string.
ENDCLASS.



CLASS zzxxmla1_main_endpoint IMPLEMENTATION.

  METHOD if_http_extension~handle_request.
    " Entry point of the olap4abap server (XMLA over HTTP).
    " /schema/api/... below the node is the schema generator's API (ZZXXMLA1_CL_SCHEMA_API), the rest of /schema/...
    " its app (ZZXXMLA1_CL_WEB_APP), strings in and out.
    DATA(path_info) = server->request->get_header_field( '~path_info' ).
    IF zzxxmla1_cl_schema_api=>is_api( path_info ).
      handle_schema_api( server = server path = path_info ).
      RETURN.
    ENDIF.
    IF zzxxmla1_cl_web_app=>is_app( path_info ).
      handle_web_app( server = server path = path_info ).
      RETURN.
    ENDIF.
    " XMLA requests are SOAP envelopes sent with POST.
    CASE server->request->get_method( ).
      WHEN 'GET'.
        server->response->set_status( code = 200 reason = 'OK' ).
        server->response->set_content_type( 'text/html; charset=utf-8' ).
        server->response->set_cdata( get_description_html( ) ).

      WHEN 'POST'.
        " the handler works on strings only; this method just moves them between HTTP and the handler
        DATA(url) = get_endpoint_url( server ).
        DATA(result) = NEW zzxxmla1_cl_xmla_handler( )->handle( request = server->request->get_cdata( ) url = url ).
        server->response->set_status( code = result-status reason = COND #( WHEN result-status = 200 THEN 'OK' ELSE 'Internal Server Error' ) ).
        server->response->set_content_type( 'text/xml; charset=utf-8' ).
        server->response->set_cdata( result-body ).

      WHEN OTHERS.
        server->response->set_status( code = 405 reason = 'Method Not Allowed' ).
        server->response->set_header_field( name = 'Allow' value = 'GET, POST' ).
    ENDCASE.
  ENDMETHOD.

  METHOD handle_schema_api.
    DATA fields TYPE tihttpnvp.
    server->request->get_form_fields( CHANGING fields = fields ).
    DATA(request) = VALUE zzxxmla1_cl_schema_api=>ty_request( method = server->request->get_method( )
                                                               path   = path
                                                               body   = server->request->get_cdata( ) ).
    LOOP AT fields INTO DATA(field).
      APPEND VALUE #( name = to_lower( field-name ) value = field-value ) TO request-parameters.
    ENDLOOP.
    DATA(result) = NEW zzxxmla1_cl_schema_api( )->handle( request ).
    server->response->set_status( code = result-status reason = SWITCH #( result-status
                                                                           WHEN 200 THEN `OK`
                                                                           WHEN 400 THEN `Bad Request`
                                                                           WHEN 404 THEN `Not Found`
                                                                           WHEN 405 THEN `Method Not Allowed`
                                                                           ELSE `Internal Server Error` ) ).
    IF result-allow IS NOT INITIAL.
      server->response->set_header_field( name = 'Allow' value = result-allow ).
    ENDIF.
    server->response->set_content_type( result-content_type ).
    server->response->set_cdata( result-body ).
  ENDMETHOD.

  METHOD handle_web_app.
    " ~path_info has no trailing / (/schema/ arrives as /schema), the app's folder needs it: taken from the request URI
    DATA(uri) = server->request->get_header_field( '~request_uri' ).
    SPLIT uri AT '?' INTO uri DATA(query) ##NEEDED.
    DATA(result) = NEW zzxxmla1_cl_web_app( )->handle( method = server->request->get_method( )
                                                      path   = COND #( WHEN uri CP '*/' THEN |{ path }/| ELSE path )
                                                      query  = server->request->get_header_field( '~query_string' ) ).
    server->response->set_status( code = result-status reason = SWITCH #( result-status
                                                                           WHEN 200 THEN `OK`
                                                                           WHEN 301 THEN `Moved Permanently`
                                                                           WHEN 404 THEN `Not Found`
                                                                           ELSE `Method Not Allowed` ) ).
    IF result-allow IS NOT INITIAL.
      server->response->set_header_field( name = 'Allow' value = result-allow ).
    ENDIF.
    IF result-location IS NOT INITIAL.
      server->response->set_header_field( name = 'Location' value = result-location ).
    ENDIF.
    " the files change with every upload: the browser fetches them again (they are small, no ETag)
    server->response->set_header_field( name = 'Cache-Control' value = 'no-cache' ).
    server->response->set_content_type( result-content_type ).
    server->response->set_cdata( result-body ).
  ENDMETHOD.

  METHOD get_endpoint_url.
    DATA(path) = server->request->get_header_field( '~request_uri' ).
    SPLIT path AT '?' INTO path DATA(query).
    result = |{ COND string( WHEN server->ssl_active IS INITIAL THEN `http` ELSE `https` ) }://{ server->request->get_header_field( 'host' ) }{ path }|.
  ENDMETHOD.

  METHOD get_description_html.
    result =
      `<!DOCTYPE html>` &&
      `<html><head><meta charset="utf-8"><title>olap4abap</title></head>` &&
      `<body>` &&
      `<h1>olap4abap</h1>` &&
      `<p>This endpoint is an XMLA (XML for Analysis) server implemented in ABAP.</p>` &&
      `<p>Send XMLA requests (SOAP envelopes) to this URL using HTTP POST.</p>` &&
      `<p>Status: under development, request processing is not implemented yet.</p>` &&
      `</body></html>`.
  ENDMETHOD.

ENDCLASS.
