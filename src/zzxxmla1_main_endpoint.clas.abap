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
    "! The page a browser gets (GET): what the endpoint is and links to the apps below /schema/.
    "! @parameter base | path of the ICF service (no trailing /)
    "! @parameter query | query string of the request, kept on the links and the URL (sap-client added if missing)
    "! @parameter url | the endpoint's URL, for XMLA clients
    METHODS get_description_html
      IMPORTING base          TYPE string
                query         TYPE string
                url           TYPE string
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
        DATA(base) = server->request->get_header_field( '~script_name' ).
        server->response->set_cdata( get_description_html(
                                         base  = COND #( WHEN base CP '*/' THEN substring( val = base len = strlen( base ) - 1 ) ELSE base )
                                         query = server->request->get_header_field( '~query_string' )
                                         url   = get_endpoint_url( server ) ) ).

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
    " the client is always named: a client that is not the server's default (S/4HANA systems) needs it
    DATA(full_query) = COND string( WHEN to_lower( query ) CS `sap-client=` THEN query
                                    WHEN query IS INITIAL THEN |sap-client={ sy-mandt }|
                                    ELSE |{ query }&sap-client={ sy-mandt }| ).
    DATA(search) = |?{ full_query }|.
    DATA(apps) = |{ escape( val = base format = cl_abap_format=>e_html_attr ) }/schema/|.
    DATA(args) = escape( val = search format = cl_abap_format=>e_html_attr ).
    result =
      `<!DOCTYPE html>` &&
      `<html lang="en"><head><meta charset="utf-8">` &&
      `<meta name="viewport" content="width=device-width, initial-scale=1"><title>olap4abap</title>` &&
      |<link rel="stylesheet" href="{ apps }app.css">| &&
      `<style>` &&
      `main{max-width:760px;margin:0 auto;padding:24px 16px}` &&
      `ul.apps{list-style:none;padding:0;display:grid;gap:12px}` &&
      `ul.apps a{display:block;padding:12px 16px;border:1px solid var(--line);border-radius:var(--radius);` &&
      `background:var(--panel);color:var(--text);text-decoration:none}` &&
      `ul.apps a:hover{border-color:var(--accent)}` &&
      `ul.apps b{color:var(--accent)}ul.apps span{display:block;color:var(--muted);margin-top:4px}` &&
      `code{font-family:var(--mono);background:var(--sunken);padding:2px 6px;border-radius:4px;word-break:break-all}` &&
      `</style></head>` &&
      `<body><main>` &&
      `<h1>olap4abap</h1>` &&
      `<p>An XMLA (XML for Analysis) server with its own MDX engine, serving cubes on SAP BW data.</p>` &&
      `<h2>Applications</h2>` &&
      `<ul class="apps">` &&
      |<li><a href="{ apps }{ args }"><b>Schema Builder</b>| &&
      `<span>Propose a schema for an InfoCube or aDSO, edit it and accept it into a catalog.</span></a></li>` &&
      |<li><a href="{ apps }console.html{ args }"><b>MDX Console</b>| &&
      `<span>Browse a catalog's cubes and run MDX queries against this endpoint.</span></a></li>` &&
      |<li><a href="{ apps }time.html{ args }"><b>Time Master Data</b>| &&
      `<span>Fill the SID and attribute tables of BW's calendar characteristics.</span></a></li>` &&
      `</ul>` &&
      `<h2>XMLA clients</h2>` &&
      `<p>Excel and other XMLA clients connect to this URL; requests are SOAP envelopes sent with POST:</p>` &&
      |<p><code>{ escape( val = url && search format = cl_abap_format=>e_html_text ) }</code></p>| &&
      `<p><a href="https://github.com/arcanist123/olap4abap">olap4abap on GitHub</a></p>` &&
      `</main></body></html>`.
  ENDMETHOD.

ENDCLASS.
