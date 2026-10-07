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
    TYPES ty_metadata TYPE zzxxmla1_cl_bw_view_gen=>ty_metadata.

    "! the store of the FoodMart cube: attributes without texts
    METHODS store
      RETURNING VALUE(result) TYPE ty_metadata.
    "! the product of the demo cube 0D_NW_C01: a text without language, a time-independent navigation attribute
    "! with texts in EN and DE, a time-dependent one
    METHODS product
      RETURNING VALUE(result) TYPE ty_metadata.
    "! the DDL of a customer characteristic: SID, key and attributes, NUMC as numbers by length, OBJVERS and CHANGED
    "! left out, the /BIC/ namespace dropped from the column names
    METHODS customer_characteristic FOR TESTING.
    "! texts in EN at the key date with the key in their place where there is none, time-dependent attributes at the
    "! key date (docs/bw-schema-design-guide.md, section 4)
    METHODS texts_and_time_dependent FOR TESTING.
    "! the columns say whose value or text they are
    METHODS columns_of_product FOR TESTING.
    "! a client-dependent text table, and one whose key has a field the view lacks, are left out with a note
    METHODS texts_left_out FOR TESTING.
    "! compounding: the key fields of the SID table are in the view, and the joins use them all
    METHODS compounded FOR TESTING.
    "! a characteristic without attribute table: the SID table alone
    METHODS without_attributes FOR TESTING.
    "! no SID table, no view
    METHODS without_sids FOR TESTING.
    "! any namespace is dropped from a view column, not only /BIC/
    METHODS view_column FOR TESTING.
    "! a characteristic in a namespace: the DDL source is named by the view's number, the label by the characteristic
    METHODS namespace_characteristic FOR TESTING.
    "! the placeholder of a view not generated yet gives back its characteristic, a view name none
    METHODS placeholder FOR TESTING.
    "! BW's names of the tables of a characteristic of the FoodMart cube
    METHODS tables_of_zfmstore FOR TESTING.
    "! a reference characteristic of the demo cube 0D_NW_C01 has the tables and key of the one it references
    METHODS tables_of_reference FOR TESTING.
ENDCLASS.

CLASS ltc_bw_view_gen IMPLEMENTATION.

  METHOD store.
    result = VALUE #(
      characteristic = 'ZFMSTORE'
      tables         = VALUE #( basic = 'ZFMSTORE' sids = '/BIC/SZFMSTORE' attributes = '/BIC/PZFMSTORE'
                                key_field = '/BIC/ZFMSTORE' )
      sid_columns       = VALUE #( ( field = '/BIC/ZFMSTORE' datatype = 'NUMC' length = 10 key = abap_true )
                                   ( field = 'SID'           datatype = 'INT4' length = 10 )
                                   ( field = 'CHCKFL'        datatype = 'CHAR' length = 1 ) )
      attribute_columns = VALUE #( ( field = '/BIC/ZFMSTORE' datatype = 'NUMC' length = 10 key = abap_true )
                                   ( field = 'OBJVERS'       datatype = 'CHAR' length = 1 key = abap_true )
                                   ( field = 'CHANGED'       datatype = 'CHAR' length = 1 )
                                   ( field = '/BIC/ZFMSNAME' datatype = 'CHAR' length = 60 )
                                   ( field = '/BIC/ZFMYEAR'  datatype = 'NUMC' length = 4 )
                                   ( field = '/BIC/ZFMSQFT'  datatype = 'NUMC' length = 60 ) )
      attributes        = VALUE #( ( iobjnm = 'ZFMSNAME' field = '/BIC/ZFMSNAME' )
                                   ( iobjnm = 'ZFMYEAR'  field = '/BIC/ZFMYEAR' )
                                   ( iobjnm = 'ZFMSQFT'  field = '/BIC/ZFMSQFT' ) ) ).
  ENDMETHOD.

  METHOD product.
    result = VALUE #(
      characteristic = '0D_NW_PROD'
      tables         = VALUE #( basic = '0D_NW_PROD' sids = '/BI0/SD_NW_PROD' attributes = '/BI0/PD_NW_PROD'
                                time_attributes = '/BI0/QD_NW_PROD' texts = '/BI0/TD_NW_PROD' key_field = 'D_NW_PROD' )
      sid_columns            = VALUE #( ( field = 'D_NW_PROD' datatype = 'CHAR' length = 60 key = abap_true )
                                        ( field = 'SID'       datatype = 'INT4' length = 10 ) )
      attribute_columns      = VALUE #( ( field = 'D_NW_PROD'  datatype = 'CHAR' length = 60 key = abap_true )
                                        ( field = 'OBJVERS'    datatype = 'CHAR' length = 1 key = abap_true )
                                        ( field = 'CHANGED'    datatype = 'CHAR' length = 1 )
                                        ( field = 'D_NW_PRDCT' datatype = 'CHAR' length = 8 ) )
      time_attribute_columns = VALUE #( ( field = 'D_NW_PROD'  datatype = 'CHAR' length = 60 key = abap_true )
                                        ( field = 'OBJVERS'    datatype = 'CHAR' length = 1 key = abap_true )
                                        ( field = 'DATETO'     datatype = 'DATS' length = 8 key = abap_true )
                                        ( field = 'CHANGED'    datatype = 'CHAR' length = 1 )
                                        ( field = 'DATEFROM'   datatype = 'DATS' length = 8 )
                                        ( field = 'D_NW_PRDGP' datatype = 'CHAR' length = 10 ) )
      texts      = VALUE #( name = '/BI0/TD_NW_PROD' key_field = 'D_NW_PROD'
                            columns = VALUE #( ( field = 'D_NW_PROD' datatype = 'CHAR' length = 60 key = abap_true )
                                               ( field = 'TXTSH'     datatype = 'CHAR' length = 20 )
                                               ( field = 'TXTMD'     datatype = 'CHAR' length = 40 ) ) )
      attributes = VALUE #(
        ( iobjnm = '0D_NW_PRDCT' field = 'D_NW_PRDCT' navigation = abap_true
          texts = VALUE #( name = '/BI0/TD_NW_PRDCT' key_field = 'D_NW_PRDCT'
                           columns = VALUE #( ( field = 'LANGU'      datatype = 'LANG' length = 1 key = abap_true )
                                              ( field = 'D_NW_PRDCT' datatype = 'CHAR' length = 8 key = abap_true )
                                              ( field = 'TXTSH'      datatype = 'CHAR' length = 20 )
                                              ( field = 'TXTMD'      datatype = 'CHAR' length = 40 ) ) ) )
        ( iobjnm = '0D_NW_PRDGP' field = 'D_NW_PRDGP' navigation = abap_true
          texts = VALUE #( name = '/BI0/TD_NW_PRDGP' key_field = 'D_NW_PRDGP'
                           columns = VALUE #( ( field = 'LANGU'      datatype = 'LANG' length = 1 key = abap_true )
                                              ( field = 'D_NW_PRDGP' datatype = 'CHAR' length = 10 key = abap_true )
                                              ( field = 'TXTLG'      datatype = 'CHAR' length = 60 ) ) ) ) ) ).
  ENDMETHOD.

  METHOD customer_characteristic.
    DATA(nl) = cl_abap_char_utilities=>newline.
    DATA(act) = zzxxmla1_cl_bw_view_gen=>ddl_source(
      characteristic = 'ZFMSTORE'
      view_name      = 'ZZXXMLA1V0000003'
      layout         = zzxxmla1_cl_bw_view_gen=>build_layout( store( ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = act
      exp = |@AbapCatalog.sqlViewName: 'ZZXXMLA1V0000003'| && nl &&
            |@AbapCatalog.compiler.compareFilter: true| && nl &&
            |@AccessControl.authorizationCheck: #NOT_REQUIRED| && nl &&
            |@EndUserText.label: 'BW characteristic ZFMSTORE: SID with active attributes'| && nl &&
            |define view ZZXXMLA1_C0000003| && nl &&
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

  METHOD texts_and_time_dependent.
    DATA(nl) = cl_abap_char_utilities=>newline.
    DATA(layout) = zzxxmla1_cl_bw_view_gen=>build_layout( product( ) ).
    cl_abap_unit_assert=>assert_initial( layout-notes ).
    DATA(act) = zzxxmla1_cl_bw_view_gen=>ddl_source( characteristic = '0D_NW_PROD'
                                                     view_name      = 'ZZXXMLA1V0000012'
                                                     layout         = layout ).
    cl_abap_unit_assert=>assert_char_cp(
      act = act
      exp = |*  as select from /bi0/sd_nw_prod as s{ nl }| &&
            |    left outer join /bi0/pd_nw_prod as p on  p.d_nw_prod = s.d_nw_prod{ nl }| &&
            |                                        and p.objvers = 'A'{ nl }| &&
            |    left outer join /bi0/qd_nw_prod as q on  q.d_nw_prod = s.d_nw_prod{ nl }| &&
            |                                        and q.objvers = 'A'{ nl }| &&
            |                                        and q.dateto = '99991231'{ nl }| &&
            |    left outer join /bi0/td_nw_prod as t on  t.d_nw_prod = s.d_nw_prod{ nl }| &&
            |    left outer join /bi0/td_nw_prdct as t1 on  t1.langu = 'E'{ nl }| &&
            |                                        and t1.d_nw_prdct = p.d_nw_prdct{ nl }| &&
            |    left outer join /bi0/td_nw_prdgp as t2 on  t2.langu = 'E'{ nl }| &&
            |                                        and t2.d_nw_prdgp = q.d_nw_prdgp{ nl }| &&
            |\{{ nl }| &&
            |  key s.sid as SID,{ nl }| &&
            |      s.d_nw_prod as D_NW_PROD,{ nl }| &&
            |      coalesce( t.txtmd, s.d_nw_prod ) as TXTMD,{ nl }| &&
            |      p.d_nw_prdct as D_NW_PRDCT,{ nl }| &&
            |      coalesce( t1.txtmd, p.d_nw_prdct ) as D_NW_PRDCT_TXT,{ nl }| &&
            |      q.d_nw_prdgp as D_NW_PRDGP,{ nl }| &&
            |      coalesce( t2.txtlg, q.d_nw_prdgp ) as D_NW_PRDGP_TXT{ nl }| &&
            |\}{ nl }| ).
  ENDMETHOD.

  METHOD columns_of_product.
    DATA(columns) = zzxxmla1_cl_bw_view_gen=>build_layout( product( ) )-columns.
    cl_abap_unit_assert=>assert_equals(
      act = VALUE string_table( FOR c IN columns ( |{ c-name } { c-iobjnm } { c-text } { c-navigation }| ) )
      exp = VALUE string_table( ( `SID   ` ) ( `D_NW_PROD 0D_NW_PROD  ` ) ( `TXTMD 0D_NW_PROD X ` )
                                ( `D_NW_PRDCT 0D_NW_PRDCT  X` ) ( `D_NW_PRDCT_TXT 0D_NW_PRDCT X ` )
                                ( `D_NW_PRDGP 0D_NW_PRDGP  X` ) ( `D_NW_PRDGP_TXT 0D_NW_PRDGP X ` ) ) ).
  ENDMETHOD.

  METHOD texts_left_out.
    DATA(metadata) = product( ).
    READ TABLE metadata-attributes ASSIGNING FIELD-SYMBOL(<category>) INDEX 1.
    INSERT VALUE #( field = 'MANDT' datatype = 'CLNT' length = 3 key = abap_true )
      INTO <category>-texts-columns INDEX 1.
    READ TABLE metadata-attributes ASSIGNING FIELD-SYMBOL(<group>) INDEX 2.
    INSERT VALUE #( field = 'D_NW_CNTRY' datatype = 'CHAR' length = 3 key = abap_true )
      INTO <group>-texts-columns INDEX 1.
    DATA(layout) = zzxxmla1_cl_bw_view_gen=>build_layout( metadata ).
    cl_abap_unit_assert=>assert_equals(
      act = layout-notes
      exp = VALUE zzxxmla1_cl_bw_view_gen=>ty_t_note(
              ( iobjnm = `0D_NW_PRDCT` reason = `text not in the view: /BI0/TD_NW_PRDCT is client-dependent` )
              ( iobjnm = `0D_NW_PRDGP`
                reason = `text not in the view: key field D_NW_CNTRY of /BI0/TD_NW_PRDGP is not in the view` ) ) ).
    cl_abap_unit_assert=>assert_false( xsdbool( line_exists( layout-columns[ name = `D_NW_PRDCT_TXT` ] ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( layout-joins ) exp = 3 ).
  ENDMETHOD.

  METHOD compounded.
    " region, compounded with country: both are keys of the SID, attribute and text tables
    DATA(metadata) = VALUE ty_metadata(
      characteristic = '0D_NW_REGIO'
      tables         = VALUE #( basic = '0D_NW_REGIO' sids = '/BI0/SD_NW_REGIO' attributes = '/BI0/PD_NW_REGIO'
                                texts = '/BI0/TD_NW_REGIO' key_field = 'D_NW_REGIO' )
      sid_columns       = VALUE #( ( field = 'D_NW_CNTRY' datatype = 'CHAR' length = 3 key = abap_true )
                                   ( field = 'D_NW_REGIO' datatype = 'CHAR' length = 3 key = abap_true )
                                   ( field = 'SID'        datatype = 'INT4' length = 10 ) )
      attribute_columns = VALUE #( ( field = 'D_NW_CNTRY' datatype = 'CHAR' length = 3 key = abap_true )
                                   ( field = 'D_NW_REGIO' datatype = 'CHAR' length = 3 key = abap_true )
                                   ( field = 'OBJVERS'    datatype = 'CHAR' length = 1 key = abap_true )
                                   ( field = 'CHANGED'    datatype = 'CHAR' length = 1 ) )
      texts = VALUE #( name = '/BI0/TD_NW_REGIO' key_field = 'D_NW_REGIO'
                       columns = VALUE #( ( field = 'D_NW_CNTRY' datatype = 'CHAR' length = 3 key = abap_true )
                                          ( field = 'D_NW_REGIO' datatype = 'CHAR' length = 3 key = abap_true )
                                          ( field = 'TXTMD'      datatype = 'CHAR' length = 40 ) ) ) ).
    DATA(layout) = zzxxmla1_cl_bw_view_gen=>build_layout( metadata ).
    cl_abap_unit_assert=>assert_equals(
      act = layout-joins
      exp = VALUE zzxxmla1_cl_bw_view_gen=>ty_t_join(
              ( table = '/BI0/PD_NW_REGIO' alias = `p`
                conditions = VALUE #( ( `p.d_nw_cntry = s.d_nw_cntry` ) ( `p.d_nw_regio = s.d_nw_regio` )
                                      ( `p.objvers = 'A'` ) ) )
              ( table = '/BI0/TD_NW_REGIO' alias = `t`
                conditions = VALUE #( ( `t.d_nw_cntry = s.d_nw_cntry` ) ( `t.d_nw_regio = s.d_nw_regio` ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = VALUE string_table( FOR c IN layout-columns ( |{ c-name } { c-iobjnm }| ) )
      exp = VALUE string_table( ( `SID ` ) ( `D_NW_CNTRY ` ) ( `D_NW_REGIO 0D_NW_REGIO` ) ( `TXTMD 0D_NW_REGIO` ) ) ).
  ENDMETHOD.

  METHOD without_attributes.
    DATA(nl) = cl_abap_char_utilities=>newline.
    DATA(act) = zzxxmla1_cl_bw_view_gen=>ddl_source(
      characteristic = 'ZDOC'
      view_name      = 'ZZXXMLA1V0000010'
      layout         = zzxxmla1_cl_bw_view_gen=>build_layout( VALUE #(
                         characteristic = 'ZDOC'
                         tables         = VALUE #( basic = 'ZDOC' sids = '/ABC/SZDOC' key_field = '/ABC/ZDOC' )
                         sid_columns    = VALUE #( ( field = '/ABC/ZDOC' datatype = 'CHAR' length = 10 key = abap_true )
                                                   ( field = 'SID' datatype = 'INT4' length = 10 ) ) ) ) ).
    cl_abap_unit_assert=>assert_char_cp(
      act = act
      exp = |*define view ZZXXMLA1_C0000010{ nl }  as select from /abc/szdoc as s{ nl }\{{ nl }| &&
            |  key s.sid as SID,{ nl }      s./abc/zdoc as ZDOC{ nl }\}*| ).
    cl_abap_unit_assert=>assert_char_np( act = act exp = '*join*' ).
  ENDMETHOD.

  METHOD without_sids.
    DATA(layout) = zzxxmla1_cl_bw_view_gen=>build_layout( VALUE #( characteristic = '0CALDAY'
                                                                   tables = VALUE #( basic = '0CALDAY' ) ) ).
    cl_abap_unit_assert=>assert_initial( layout-columns ).
  ENDMETHOD.

  METHOD view_column.
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_bw_view_gen=>view_column( '/BIC/ZFMSNAME' ) exp = `ZFMSNAME` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_bw_view_gen=>view_column( '/ABC/ZDOC' ) exp = `ZDOC` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_bw_view_gen=>view_column( 'MATL_GROUP' ) exp = `MATL_GROUP` ).
  ENDMETHOD.

  METHOD namespace_characteristic.
    DATA(act) = zzxxmla1_cl_bw_view_gen=>ddl_source(
      characteristic = '/1BW/D01'
      view_name      = 'ZZXXMLA1V0000011'
      layout         = zzxxmla1_cl_bw_view_gen=>build_layout( VALUE #(
                         characteristic = '/1BW/D01'
                         tables         = VALUE #( basic = '/1BW/D01' sids = '/1B0/SD01' key_field = '/1B0/S_D01' )
                         sid_columns    = VALUE #( ( field = '/1B0/S_D01' datatype = 'CHAR' length = 10
                                                     key = abap_true ) ) ) ) ).
    cl_abap_unit_assert=>assert_char_cp( act = act exp = |*@EndUserText.label: 'BW characteristic /1BW/D01: *| ).
    cl_abap_unit_assert=>assert_char_cp( act = act exp = '*define view ZZXXMLA1_C0000011*' ).
    cl_abap_unit_assert=>assert_char_cp( act = act exp = '*s./1b0/s_d01 as S_D01*' ).
  ENDMETHOD.

  METHOD placeholder.
    DATA(placeholder) = zzxxmla1_cl_bw_view_gen=>placeholder( '/1BW/D01' ).
    cl_abap_unit_assert=>assert_equals( act = placeholder exp = `ZZXXMLA1_C_/1BW/D01` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_bw_view_gen=>characteristic_of_placeholder( placeholder )
                                        exp = `/1BW/D01` ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_bw_view_gen=>characteristic_of_placeholder( `ZZXXMLA1V0000011` ) ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_bw_view_gen=>characteristic_of_placeholder( `ZZXXMLA1_C0000011` ) ).
  ENDMETHOD.

  METHOD tables_of_zfmstore.
    cl_abap_unit_assert=>assert_equals(
      act = NEW zzxxmla1_cl_bw_view_gen( )->tables( 'ZFMSTORE' )
      exp = VALUE zzxxmla1_cl_bw_view_gen=>ty_tables( basic      = 'ZFMSTORE'
                                                      sids       = '/BIC/SZFMSTORE'
                                                      attributes = '/BIC/PZFMSTORE'
                                                      key_field  = '/BIC/ZFMSTORE' ) ).
  ENDMETHOD.

  METHOD tables_of_reference.
    cl_abap_unit_assert=>assert_equals(
      act = NEW zzxxmla1_cl_bw_view_gen( )->tables( '0D_NW_SOLD' )
      exp = VALUE zzxxmla1_cl_bw_view_gen=>ty_tables( basic      = '0D_NW_CUST'
                                                      sids       = '/BI0/SD_NW_CUST'
                                                      attributes = '/BI0/PD_NW_CUST'
                                                      texts      = '/BI0/TD_NW_CUST'
                                                      key_field  = 'D_NW_CUST' ) ).
  ENDMETHOD.

ENDCLASS.
