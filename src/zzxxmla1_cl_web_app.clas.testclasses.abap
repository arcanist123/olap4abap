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
"! The app's routing; no test reads a real file (the app's files are uploaded separately).
CLASS ltc_web_app DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    METHODS app_paths FOR TESTING.
    METHODS redirect_to_folder FOR TESTING.
    METHODS only_get FOR TESTING.
    METHODS missing_file FOR TESTING.
    METHODS file_paths FOR TESTING.
    METHODS content_types FOR TESTING.
ENDCLASS.

CLASS zzxxmla1_cl_web_app DEFINITION LOCAL FRIENDS ltc_web_app.

CLASS ltc_web_app IMPLEMENTATION.

  METHOD app_paths.
    cl_abap_unit_assert=>assert_true( zzxxmla1_cl_web_app=>is_app( `/schema` ) ).
    cl_abap_unit_assert=>assert_true( zzxxmla1_cl_web_app=>is_app( `/schema/` ) ).
    cl_abap_unit_assert=>assert_true( zzxxmla1_cl_web_app=>is_app( `/schema/app.js` ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_web_app=>is_app( `/schema/api/providers` ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_web_app=>is_app( `/schemas` ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_web_app=>is_app( `` ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_web_app=>is_app( `/WEB-INF/datasources.xml` ) ).
  ENDMETHOD.

  METHOD redirect_to_folder.
    DATA(result) = NEW zzxxmla1_cl_web_app( )->handle( method = `GET` path = `/schema` query = `sap-client=001` ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 301 ).
    cl_abap_unit_assert=>assert_equals( act = result-location exp = `schema/?sap-client=001` ).
    result = NEW zzxxmla1_cl_web_app( )->handle( method = `GET` path = `/schema` ).
    cl_abap_unit_assert=>assert_equals( act = result-location exp = `schema/` ).
  ENDMETHOD.

  METHOD only_get.
    DATA(result) = NEW zzxxmla1_cl_web_app( )->handle( method = `POST` path = `/schema/` ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 405 ).
    cl_abap_unit_assert=>assert_equals( act = result-allow exp = `GET` ).
  ENDMETHOD.

  METHOD missing_file.
    DATA(result) = NEW zzxxmla1_cl_web_app( )->handle( method = `GET` path = `/schema/no/such/file.js` ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 404 ).
    result = NEW zzxxmla1_cl_web_app( )->handle( method = `GET` path = `/schema/../WEB-INF/datasources.xml` ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 404 ).
  ENDMETHOD.

  METHOD file_paths.
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_web_app=>file_path( `/schema/` )
                                        exp = `/schema/index.html` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_web_app=>file_path( `/schema/vendor/x.mjs` )
                                        exp = `/schema/vendor/x.mjs` ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_web_app=>file_path( `/schema/../WEB-INF/datasources.xml` ) ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_web_app=>file_path( `/WEB-INF/datasources.xml` ) ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_web_app=>file_path( `/schema` ) ).
  ENDMETHOD.

  METHOD content_types.
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_web_app=>content_type( `/schema/index.html` )
                                        exp = `text/html; charset=utf-8` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_web_app=>content_type( `/schema/App.JS` )
                                        exp = `text/javascript; charset=utf-8` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_web_app=>content_type( `/schema/vendor/htm.mjs` )
                                        exp = `text/javascript; charset=utf-8` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_web_app=>content_type( `/schema/app.css` )
                                        exp = `text/css; charset=utf-8` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_web_app=>content_type( `/schema/README` )
                                        exp = `text/plain; charset=utf-8` ).
  ENDMETHOD.

ENDCLASS.
