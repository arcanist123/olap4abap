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
CLASS ltc_bw_view_gen DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.

  PRIVATE SECTION.

    "! the DDL of a customer characteristic: SID, key and attributes, NUMC as numbers by length, OBJVERS and CHANGED

    "! left out, the /BIC/ namespace dropped from the column names

    METHODS customer_characteristic FOR TESTING.

    "! an SAP characteristic (leading 0): /BI0/ tables, field names without namespace

    METHODS sap_characteristic FOR TESTING.

    "! a characteristic without attribute table: the SID table alone

    METHODS without_attributes FOR TESTING.

    "! any namespace is dropped from a view column, not only /BIC/

    METHODS view_column FOR TESTING.

    "! BW's names of the tables of a characteristic of the FoodMart cube

    METHODS tables_of_zfmstore FOR TESTING.

ENDCLASS.



CLASS ltc_bw_view_gen IMPLEMENTATION.



  METHOD customer_characteristic.

    DATA(nl) = cl_abap_char_utilities=>newline.

    DATA(act) = NEW zzxxmla1_cl_bw_view_gen( )->ddl_source(

      characteristic = 'ZFMSTORE'

      view_name      = 'ZZXXMLA1V0000003'

      tables         = VALUE #( sids = '/BIC/SZFMSTORE' attributes = '/BIC/PZFMSTORE' key_field = '/BIC/ZFMSTORE' )

      columns        = VALUE #( ( field = '/BIC/ZFMSTORE' datatype = 'NUMC' length = 10 )

                                ( field = 'OBJVERS'       datatype = 'CHAR' length = 1 )

                                ( field = 'CHANGED'       datatype = 'CHAR' length = 1 )

                                ( field = '/BIC/ZFMSNAME' datatype = 'CHAR' length = 60 )

                                ( field = '/BIC/ZFMYEAR'  datatype = 'NUMC' length = 4 )

                                ( field = '/BIC/ZFMSQFT'  datatype = 'NUMC' length = 60 ) ) ).

    cl_abap_unit_assert=>assert_equals(

      act = act

      exp = |@AbapCatalog.sqlViewName: 'ZZXXMLA1V0000003'| && nl &&

            |@AbapCatalog.compiler.compareFilter: true| && nl &&

            |@AccessControl.authorizationCheck: #NOT_REQUIRED| && nl &&

            |@EndUserText.label: 'BW characteristic ZFMSTORE: SID with active attributes'| && nl &&

            |define view ZZXXMLA1_C_ZFMSTORE| && nl &&

            |  as select from /bic/szfmstore as s| && nl &&

            |    left outer join /bic/pzfmstore as p on  p./bic/zfmstore = s./bic/zfmstore| && nl &&

            |                                        and p.objvers = 'A'| && nl &&

            |\{| && nl &&

            |  key s.sid as SID,| && nl &&

            |      cast( s./bic/zfmstore as abap.int8 ) as ZFMSTORE,| && nl &&

            |      p./bic/zfmsname as ZFMSNAME,| && nl &&

            |      cast( p./bic/zfmyear as abap.int4 ) as ZFMYEAR,| && nl &&

            |      cast( p./bic/zfmsqft as abap.dec(31,0) ) as ZFMSQFT| && nl &&

            |\}| && nl ).

  ENDMETHOD.



  METHOD sap_characteristic.

    DATA(act) = NEW zzxxmla1_cl_bw_view_gen( )->ddl_source(

      characteristic = '0MATERIAL'

      view_name      = 'ZZXXMLA1V0000009'

      tables         = VALUE #( sids = '/BI0/SMATERIAL' attributes = '/BI0/PMATERIAL' key_field = 'MATERIAL' )

      columns        = VALUE #( ( field = 'MATERIAL'   datatype = 'CHAR' length = 18 )

                                ( field = 'MATL_GROUP' datatype = 'CHAR' length = 9 ) ) ).

    cl_abap_unit_assert=>assert_char_cp( act = act exp = '*as select from /bi0/smaterial as s*' ).

    cl_abap_unit_assert=>assert_char_cp( act = act exp = '*left outer join /bi0/pmaterial as p on  p.material = s.material*' ).

    cl_abap_unit_assert=>assert_char_cp( act = act exp = '*define view ZZXXMLA1_C_0MATERIAL*' ).

    cl_abap_unit_assert=>assert_char_cp( act = act exp = '*p.matl_group as MATL_GROUP*' ).

  ENDMETHOD.



  METHOD without_attributes.

    DATA(nl) = cl_abap_char_utilities=>newline.

    DATA(act) = NEW zzxxmla1_cl_bw_view_gen( )->ddl_source(

      characteristic = 'ZDOC'

      view_name      = 'ZZXXMLA1V0000010'

      tables         = VALUE #( sids = '/ABC/SZDOC' key_field = '/ABC/ZDOC' )

      columns        = VALUE #( ( field = '/ABC/ZDOC' datatype = 'CHAR' length = 10 ) ) ).

    cl_abap_unit_assert=>assert_char_cp(

      act = act

      exp = |*define view ZZXXMLA1_C_ZDOC{ nl }  as select from /abc/szdoc as s{ nl }\{{ nl }| &&

            |  key s.sid as SID,{ nl }      s./abc/zdoc as ZDOC{ nl }\}*| ).

    cl_abap_unit_assert=>assert_char_np( act = act exp = '*join*' ).

  ENDMETHOD.



  METHOD view_column.

    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_bw_view_gen=>view_column( '/BIC/ZFMSNAME' ) exp = `ZFMSNAME` ).

    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_bw_view_gen=>view_column( '/ABC/ZDOC' ) exp = `ZDOC` ).

    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_bw_view_gen=>view_column( 'MATL_GROUP' ) exp = `MATL_GROUP` ).

  ENDMETHOD.



  METHOD tables_of_zfmstore.

    cl_abap_unit_assert=>assert_equals(

      act = NEW zzxxmla1_cl_bw_view_gen( )->tables( 'ZFMSTORE' )

      exp = VALUE zzxxmla1_cl_bw_view_gen=>ty_tables( sids       = '/BIC/SZFMSTORE'

                                                      attributes = '/BIC/PZFMSTORE'

                                                      key_field  = '/BIC/ZFMSTORE' ) ).

  ENDMETHOD.



ENDCLASS.
