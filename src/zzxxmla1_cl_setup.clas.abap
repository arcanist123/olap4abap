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
"! Sets up the server after the package is imported (program ZZXXMLA1_SETUP, or sapcli class execute):
"! - the tables (ZZXXMLA1_CL_CREATE_TABLES);
"! - the files below /schema/ deleted: earlier setups wrote the schema builder there, it is now served from the code
"!   (ZZXXMLA1_CL_WEB_APP_FILES);
"! - /WEB-INF/datasources.xml with one data source and no catalog, only if there is none: it holds the catalogs;
"! - on request the clinic demo (ZZXXMLA1_CL_BW_CLINIC_GEN): BW objects, data, schemas and catalogs, with at most
"!   clinic_max_visits visits if that is given;
"! - on request the wide demo (ZZXXMLA1_CL_BW_WIDE_GEN): BW objects with 100 characteristics and their data, with at
"!   wide_records records if that is given (1,000 if not).
"! It can run any number of times.
CLASS zzxxmla1_cl_setup DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    "! Sets up the server; the log of the run.
    METHODS run
      IMPORTING clinic            TYPE abap_bool DEFAULT abap_false
                clinic_max_visits TYPE i DEFAULT 0
                wide              TYPE abap_bool DEFAULT abap_false
                wide_records      TYPE i DEFAULT 0
      RETURNING VALUE(result)     TYPE string_table.
  PROTECTED SECTION.
  PRIVATE SECTION.
    METHODS delete_app_files
      RETURNING VALUE(result) TYPE string_table.
    METHODS write_datasources
      RETURNING VALUE(result) TYPE string_table.
ENDCLASS.



CLASS zzxxmla1_cl_setup IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    LOOP AT run( ) INTO DATA(line).
      out->write( line ).
    ENDLOOP.
  ENDMETHOD.

  METHOD run.
    APPEND LINES OF NEW zzxxmla1_cl_create_tables( )->run( ) TO result.
    APPEND LINES OF delete_app_files( ) TO result.
    APPEND LINES OF write_datasources( ) TO result.
    COMMIT WORK.
    IF clinic = abap_true.
      APPEND LINES OF NEW zzxxmla1_cl_bw_clinic_gen( )->run( clinic_max_visits ) TO result.
    ENDIF.
    IF wide = abap_true.
      APPEND LINES OF NEW zzxxmla1_cl_bw_wide_gen( )->run( wide_records ) TO result.
    ENDIF.
  ENDMETHOD.

  METHOD delete_app_files.
    DATA(folder) = zzxxmla1_cl_web_app=>c_path && `/`.
    LOOP AT zzxxmla1_cl_files=>list( ) INTO DATA(existing).
      IF existing-path CP |{ folder }*|.
        zzxxmla1_cl_files=>delete( existing-path ).
        APPEND |{ existing-path }: deleted, the app is served from ZZXXMLA1_CL_WEB_APP_FILES| TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD write_datasources.
    IF zzxxmla1_cl_files=>read( zzxxmla1_cl_files=>c_datasources )-path IS NOT INITIAL.
      APPEND |{ zzxxmla1_cl_files=>c_datasources }: exists| TO result.
      RETURN.
    ENDIF.
    zzxxmla1_cl_files=>write( path = zzxxmla1_cl_files=>c_datasources
                              content = zzxxmla1_cl_files=>default_datasources( ) ).
    APPEND |{ zzxxmla1_cl_files=>c_datasources }: written, one data source without catalogs| TO result.
  ENDMETHOD.

ENDCLASS.
