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
    "! the DDL of a customer characteristic: SID, key and attributes, each NUMC one as BW holds it followed by its
    "! number by length, OBJVERS and CHANGED left out, the /BIC/ namespace dropped from the column names
    METHODS customer_characteristic FOR TESTING.
    "! the number of a NUMC column whose name would be longer than 30 characters is left out with a note; the number
    "! says which column it is the number of and is no value of an InfoObject
    METHODS numc_numbers FOR TESTING.
    "! texts in EN at the key date with the key in their place where there is none, time-dependent attributes at the
    "! key date (docs/bw-schema-design-guide.md, section 4)
    METHODS texts_and_time_dependent FOR TESTING.
    "! the columns say whose value or text they are
    METHODS columns_of_product FOR TESTING.
    "! a client-dependent text table, and one whose key has a field the view lacks, are left out with a note
    METHODS texts_left_out FOR TESTING.
    "! compounding: the key fields of the SID table are in the view, and the joins use them all
    METHODS compounded FOR TESTING.
    "! the name of a value compounded once: # for an initial value, NUMC initial is all zeros
    METHODS compound_key_two FOR TESTING.
    "! compounded twice: a branch per set of initial values, the larger sets first, literals joined
    METHODS compound_key_three FOR TESTING.
    "! a room compounded with its site, in the clinic aDSO
    METHODS fact_metadata_of_room
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_view_gen=>ty_fact_metadata.
    "! the fact view of an aDSO with a compounded characteristic: every field without namespace, and its SID from
    "! its SID table joined on all key fields
    METHODS fact_view FOR TESTING.
    "! no compounded characteristic, or none whose compounding the aDSO has: no fact view
    METHODS fact_view_not_needed FOR TESTING.
    "! the fiscal period with the fiscal year variant fixed: the view filters the variant and has no COMPOUND_KEY; a
    "! fixed characteristic that is not its compounding leaves the plain view
    METHODS compounded_fixed FOR TESTING.
    "! a fixed characteristic: its view filtered on its value too (one member), its compounding first; a reference
    "! characteristic fixed leaves its basic one's view plain
    METHODS own_value_fixed FOR TESTING.
    "! an aDSO whose cube fixes the site: the facts filtered on it, and the room, compounded with the site only, still
    "! with its SID column, so that a schema keys it the same way
    METHODS fact_view_fixed_adso FOR TESTING.
    "! an InfoCube whose cube fixes the site: its fact table inner-joined to the site's SID table on the SID, the value
    "! in the WHERE
    METHODS fact_view_fixed_cube FOR TESTING.
    "! the fiscal period with its special periods excluded (restrict members) under the variant fixed (filter the
    "! cube): both filter its view, the variant fixed to one value leaves COMPOUND_KEY; the label has no quote
    METHODS compounded_range FOR TESTING.
    "! the variant restricted to two values: the view filtered on both, and still compounded
    METHODS compounding_two_values FOR TESTING.
    "! the facts are filtered on the characteristics of mode filter the cube only, by the condition of their rows
    METHODS fact_view_filter_mode FOR TESTING.
    "! fixed values are a selection of mode filter the cube with one I EQ row each
    METHODS selection_of_fixed FOR TESTING.
    "! the selection as table ZZXXMLA1_VIEW keys it: sorted by characteristic
    METHODS selection_text FOR TESTING.
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
            |      s./bic/zfmstore as ZFMSTORE,| && nl &&
            |      cast( s./bic/zfmstore as abap.int8 ) as ZFMSTORE_INT,| && nl &&
            |      p./bic/zfmsname as ZFMSNAME,| && nl &&
            |      p./bic/zfmyear as ZFMYEAR,| && nl &&
            |      cast( p./bic/zfmyear as abap.int4 ) as ZFMYEAR_INT,| && nl &&
            |      p./bic/zfmsqft as ZFMSQFT,| && nl &&
            |      cast( p./bic/zfmsqft as abap.dec(31,0) ) as ZFMSQFT_INT| && nl &&
            |\}| && nl ).
  ENDMETHOD.

  METHOD numc_numbers.
    DATA(metadata) = store( ).
    APPEND VALUE #( field = 'D_NW_LONGATTRIBUTENAME_12345' datatype = 'NUMC' length = 3 )
      TO metadata-attribute_columns.
    APPEND VALUE #( iobjnm = '0D_NW_LONG' field = 'D_NW_LONGATTRIBUTENAME_12345' ) TO metadata-attributes.
    DATA(layout) = zzxxmla1_cl_bw_view_gen=>build_layout( metadata ).
    cl_abap_unit_assert=>assert_equals(
      act = layout-notes
      exp = VALUE zzxxmla1_cl_bw_view_gen=>ty_t_note(
        ( iobjnm = '0D_NW_LONG'
          reason = `no number of D_NW_LONGATTRIBUTENAME_12345: ` &&
                   `D_NW_LONGATTRIBUTENAME_12345_INT is longer than 30 characters` ) ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( layout-columns[ name = `D_NW_LONGATTRIBUTENAME_12345` ] ) ) ).
    DATA(number) = layout-columns[ name = `ZFMYEAR_INT` ].
    cl_abap_unit_assert=>assert_equals( act = number-int_of exp = `ZFMYEAR` ).
    cl_abap_unit_assert=>assert_equals( act = number-datatype exp = `INT4` ).
    cl_abap_unit_assert=>assert_initial( number-iobjnm ).
    cl_abap_unit_assert=>assert_equals( act = layout-columns[ name = `ZFMYEAR` ]-datatype exp = `NUMC` ).
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
      exp = VALUE string_table( ( `SID ` ) ( `D_NW_CNTRY ` ) ( `D_NW_REGIO 0D_NW_REGIO` ) ( `COMPOUND_KEY ` )
                                ( `TXTMD 0D_NW_REGIO` ) ) ).
    DATA(compound_key) = layout-columns[ name = zzxxmla1_cl_bw_view_gen=>c_compound_key ].
    cl_abap_unit_assert=>assert_equals( act = compound_key-datatype exp = `CHAR` ).
    cl_abap_unit_assert=>assert_equals( act = compound_key-length exp = 7 ).
  ENDMETHOD.

  METHOD compound_key_two.
    DATA(nl) = cl_abap_char_utilities=>newline.
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_view_gen=>compound_key_expression( VALUE #(
              ( field = 'FISCVARNT' datatype = 'CHAR' length = 2 key = abap_true )
              ( field = 'FISCPER'   datatype = 'NUMC' length = 7 key = abap_true ) ) )
      exp = |case{ nl }| &&
            |             when s.fiscvarnt = ' ' and s.fiscper = '0000000' then '#/#'{ nl }| &&
            |             when s.fiscvarnt = ' ' then concat( '#/', s.fiscper ){ nl }| &&
            |             when s.fiscper = '0000000' then concat( s.fiscvarnt, '/#' ){ nl }| &&
            |             else concat( concat( s.fiscvarnt, '/' ), s.fiscper ) end| ).
  ENDMETHOD.

  METHOD compound_key_three.
    DATA(act) = zzxxmla1_cl_bw_view_gen=>compound_key_expression( VALUE #(
                  ( field = 'A' datatype = 'CHAR' length = 1 key = abap_true )
                  ( field = 'B' datatype = 'CHAR' length = 1 key = abap_true )
                  ( field = 'C' datatype = 'CHAR' length = 1 key = abap_true ) ) ).
    SPLIT act AT cl_abap_char_utilities=>newline INTO TABLE DATA(branches).
    cl_abap_unit_assert=>assert_equals(
      act = VALUE string_table( FOR b IN branches ( condense( b ) ) )
      exp = VALUE string_table(
              ( `case` )
              ( `when s.a = ' ' and s.b = ' ' and s.c = ' ' then '#/#/#'` )
              ( `when s.a = ' ' and s.b = ' ' then concat( '#/#/', s.c )` )
              ( `when s.a = ' ' and s.c = ' ' then concat( concat( '#/', s.b ), '/#' )` )
              ( `when s.b = ' ' and s.c = ' ' then concat( s.a, '/#/#' )` )
              ( `when s.a = ' ' then concat( concat( concat( '#/', s.b ), '/' ), s.c )` )
              ( `when s.b = ' ' then concat( concat( s.a, '/#/' ), s.c )` )
              ( `when s.c = ' ' then concat( concat( concat( s.a, '/' ), s.b ), '/#' )` )
              ( `else concat( concat( concat( concat( s.a, '/' ), s.b ), '/' ), s.c ) end` ) ) ).
  ENDMETHOD.

  METHOD fact_metadata_of_room.
    result = VALUE #(
      provider       = 'ZCLVISITA'
      fact_table     = '/BIC/AZCLVISITA7'
      fields         = VALUE #( ( field = 'REQTSN'        datatype = 'NUMC' length = 23 )
                                ( field = '/BIC/ZCLSITE'  datatype = 'CHAR' length = 10 iobjnm = 'ZCLSITE' )
                                ( field = '/BIC/ZCLROOM'  datatype = 'CHAR' length = 4  iobjnm = 'ZCLROOM' )
                                ( field = '/BIC/ZCLVISNO' datatype = 'DEC'  length = 17 iobjnm = 'ZCLVISNO' ) )
      compounded     = VALUE #( ( iobjnm = 'ZCLROOM' sids = '/BIC/SZCLROOM' key_field = '/BIC/ZCLROOM'
                                  compounding = VALUE #( ( iobjnm = 'ZCLSITE' field = '/BIC/ZCLSITE' ) ) ) ) ).
  ENDMETHOD.

  METHOD fact_view.
    DATA(nl) = cl_abap_char_utilities=>newline.
    DATA(layout) = zzxxmla1_cl_bw_view_gen=>build_fact_layout( fact_metadata_of_room( ) ).
    cl_abap_unit_assert=>assert_initial( layout-notes ).
    cl_abap_unit_assert=>assert_equals(
      act = VALUE string_table( FOR c IN layout-columns ( |{ c-name } { c-iobjnm } { c-sid }| ) )
      exp = VALUE string_table( ( `REQTSN  ` ) ( `ZCLSITE ZCLSITE ` ) ( `ZCLROOM ZCLROOM ` ) ( `ZCLVISNO ZCLVISNO ` )
                                ( `SID_ZCLROOM ZCLROOM X` ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_view_gen=>fact_ddl_source( provider = 'ZCLVISITA' view_name = 'ZZXXMLA1V0000090' layout = layout )
      exp = |@AbapCatalog.sqlViewName: 'ZZXXMLA1V0000090'{ nl }| &&
            |@AbapCatalog.compiler.compareFilter: true{ nl }| &&
            |@AccessControl.authorizationCheck: #NOT_REQUIRED{ nl }| &&
            |@EndUserText.label: 'BW aDSO ZCLVISITA: facts with SIDs of compounding'{ nl }| &&
            |define view ZZXXMLA1_C0000090{ nl }| &&
            |  as select from /bic/azclvisita7 as a{ nl }| &&
            |    left outer join /bic/szclroom as s1 on  s1./bic/zclsite = a./bic/zclsite{ nl }| &&
            |                                        and s1./bic/zclroom = a./bic/zclroom{ nl }| &&
            |\{{ nl }| &&
            |  a.reqtsn as REQTSN,{ nl }| &&
            |  a./bic/zclsite as ZCLSITE,{ nl }| &&
            |  a./bic/zclroom as ZCLROOM,{ nl }| &&
            |  a./bic/zclvisno as ZCLVISNO,{ nl }| &&
            |  s1.sid as SID_ZCLROOM{ nl }| &&
            |\}{ nl }| ).
  ENDMETHOD.

  METHOD fact_view_not_needed.
    DATA(metadata) = fact_metadata_of_room( ).
    CLEAR metadata-compounded.
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_bw_view_gen=>build_fact_layout( metadata )-columns ).
    " compounded with a characteristic the aDSO lacks: a note, and without another SID column no view
    metadata = fact_metadata_of_room( ).
    DELETE metadata-fields WHERE iobjnm = 'ZCLSITE'.
    DATA(layout) = zzxxmla1_cl_bw_view_gen=>build_fact_layout( metadata ).
    cl_abap_unit_assert=>assert_initial( layout-columns ).
    cl_abap_unit_assert=>assert_equals(
      act = layout-notes
      exp = VALUE zzxxmla1_cl_bw_view_gen=>ty_t_note(
              ( iobjnm = `ZCLROOM` reason = `compounded with ZCLSITE, which is not a field of the aDSO` ) ) ).
  ENDMETHOD.

  METHOD compounded_fixed.
    DATA(nl) = cl_abap_char_utilities=>newline.
    DATA(metadata) = VALUE ty_metadata(
      characteristic = '0FISCPER'
      tables         = VALUE #( basic = '0FISCPER' sids = '/BI0/SFISCPER' key_field = 'FISCPER' )
      sid_columns    = VALUE #( ( field = 'FISCVARNT' datatype = 'CHAR' length = 2 key = abap_true )
                                ( field = 'FISCPER'   datatype = 'CHAR' length = 7 key = abap_true )
                                ( field = 'SID'       datatype = 'INT4' length = 10 ) )
      compounding    = VALUE #( ( iobjnm = '0FISCVARNT' field = 'FISCVARNT' ) ) ).
    DATA(fixed) = VALUE zzxxmla1_cl_bw_view_gen=>ty_t_fixed( ( iobjnm = '0FISCVARNT' value = `K4` )
                                                              ( iobjnm = '0VERSION' value = `000` ) ).
    DATA(layout) = zzxxmla1_cl_bw_view_gen=>build_layout(
                     metadata  = metadata
                     selection = zzxxmla1_cl_bw_view_gen=>selection_of( fixed ) ).
    cl_abap_unit_assert=>assert_equals( act = layout-selection exp = `0FISCVARNT=K4` ).
    cl_abap_unit_assert=>assert_false( xsdbool( line_exists(
      layout-columns[ name = zzxxmla1_cl_bw_view_gen=>c_compound_key ] ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_view_gen=>ddl_source( characteristic = '0FISCPER'
                                                 view_name      = 'ZZXXMLA1V0000012'
                                                 layout         = layout )
      exp = |@AbapCatalog.sqlViewName: 'ZZXXMLA1V0000012'{ nl }| &&
            |@AbapCatalog.compiler.compareFilter: true{ nl }| &&
            |@AccessControl.authorizationCheck: #NOT_REQUIRED{ nl }| &&
            |@EndUserText.label: 'BW characteristic 0FISCPER: 0FISCVARNT = K4'{ nl }| &&
            |define view ZZXXMLA1_C0000012{ nl }| &&
            |  as select from /bi0/sfiscper as s{ nl }| &&
            |\{{ nl }| &&
            |  key s.sid as SID,{ nl }| &&
            |      s.fiscvarnt as FISCVARNT,{ nl }| &&
            |      s.fiscper as FISCPER{ nl }| &&
            |\}{ nl }| &&
            |where s.fiscvarnt = 'K4'{ nl }| ).
    " fixed, but not its compounding: the plain view, compounded
    layout = zzxxmla1_cl_bw_view_gen=>build_layout(
      metadata  = metadata
      selection = zzxxmla1_cl_bw_view_gen=>selection_of( VALUE #( ( iobjnm = '0VERSION' value = `000` ) ) ) ).
    cl_abap_unit_assert=>assert_initial( layout-selection ).
    cl_abap_unit_assert=>assert_initial( layout-filters ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists(
      layout-columns[ name = zzxxmla1_cl_bw_view_gen=>c_compound_key ] ) ) ).
  ENDMETHOD.

  METHOD own_value_fixed.
    DATA(metadata) = VALUE ty_metadata(
      characteristic = '0FISCPER'
      tables         = VALUE #( basic = '0FISCPER' sids = '/BI0/SFISCPER' key_field = 'FISCPER' )
      sid_columns    = VALUE #( ( field = 'FISCVARNT' datatype = 'CHAR' length = 2 key = abap_true )
                                ( field = 'FISCPER'   datatype = 'CHAR' length = 7 key = abap_true )
                                ( field = 'SID'       datatype = 'INT4' length = 10 ) )
      compounding    = VALUE #( ( iobjnm = '0FISCVARNT' field = 'FISCVARNT' ) ) ).
    DATA(fixed) = zzxxmla1_cl_bw_view_gen=>selection_of( VALUE #( ( iobjnm = '0FISCVARNT' value = `K4` )
                                                                  ( iobjnm = '0FISCPER' value = `2024001` ) ) ).
    DATA(layout) = zzxxmla1_cl_bw_view_gen=>build_layout( metadata = metadata selection = fixed ).
    cl_abap_unit_assert=>assert_equals( act = layout-selection exp = `0FISCPER=2024001;0FISCVARNT=K4` ).
    cl_abap_unit_assert=>assert_equals(
      act = layout-filters
      exp = VALUE string_table( ( `s.fiscvarnt = 'K4'` ) ( `s.fiscper = '2024001'` ) ) ).
    cl_abap_unit_assert=>assert_false( xsdbool( line_exists(
      layout-columns[ name = zzxxmla1_cl_bw_view_gen=>c_compound_key ] ) ) ).
    " the variant itself: one row
    layout = zzxxmla1_cl_bw_view_gen=>build_layout(
      metadata = VALUE #( characteristic = '0FISCVARNT'
                          tables         = VALUE #( basic = '0FISCVARNT' sids = '/BI0/SFISCVARNT' key_field = 'FISCVARNT' )
                          sid_columns    = VALUE #( ( field = 'FISCVARNT' datatype = 'CHAR' length = 2 key = abap_true )
                                                    ( field = 'SID'       datatype = 'INT4' length = 10 ) ) )
      selection = fixed ).
    cl_abap_unit_assert=>assert_equals( act = layout-selection exp = `0FISCVARNT=K4` ).
    cl_abap_unit_assert=>assert_equals( act = layout-filters exp = VALUE string_table( ( `s.fiscvarnt = 'K4'` ) ) ).
    " a reference characteristic: its view is its basic one's, not filtered
    layout = zzxxmla1_cl_bw_view_gen=>build_layout(
      metadata = VALUE #( characteristic = '0SOLD_TO'
                          tables         = VALUE #( basic = '0CUSTOMER' sids = '/BI0/SCUSTOMER' key_field = 'CUSTOMER' )
                          sid_columns    = VALUE #( ( field = 'CUSTOMER' datatype = 'CHAR' length = 10 key = abap_true )
                                                    ( field = 'SID'      datatype = 'INT4' length = 10 ) ) )
      selection = zzxxmla1_cl_bw_view_gen=>selection_of( VALUE #( ( iobjnm = '0SOLD_TO' value = `1000` ) ) ) ).
    cl_abap_unit_assert=>assert_initial( layout-selection ).
    cl_abap_unit_assert=>assert_initial( layout-filters ).
  ENDMETHOD.

  METHOD fact_view_fixed_adso.
    DATA(metadata) = fact_metadata_of_room( ).
    metadata-filtered = VALUE #( ( iobjnm = 'ZCLSITE' rows = zzxxmla1_cl_bw_selection=>equals( `NORTH` ) ) ).
    DATA(layout) = zzxxmla1_cl_bw_view_gen=>build_fact_layout( metadata ).
    cl_abap_unit_assert=>assert_initial( layout-notes ).
    cl_abap_unit_assert=>assert_equals( act = lines( layout-joins ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = layout-filters exp = VALUE string_table( ( `a./bic/zclsite = 'NORTH'` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = layout-selection exp = `ZCLSITE=NORTH` ).
    cl_abap_unit_assert=>assert_equals(
      act = VALUE string_table( FOR c IN layout-columns ( c-name ) )
      exp = VALUE string_table( ( `REQTSN` ) ( `ZCLSITE` ) ( `ZCLROOM` ) ( `ZCLVISNO` ) ( `SID_ZCLROOM` ) ) ).
  ENDMETHOD.

  METHOD fact_view_fixed_cube.
    DATA(nl) = cl_abap_char_utilities=>newline.
    DATA(metadata) = VALUE zzxxmla1_cl_bw_view_gen=>ty_fact_metadata(
      provider   = 'ZCLVISIT'
      cube       = abap_true
      fact_table = '/BIC/FZCLVISIT'
      fields     = VALUE #( ( field = 'SID_ZCLSITE'   datatype = 'INT4' length = 10 iobjnm = 'ZCLSITE' )
                            ( field = 'SID_ZCLROOM'   datatype = 'INT4' length = 10 iobjnm = 'ZCLROOM' )
                            ( field = '/BIC/ZCLVISNO' datatype = 'DEC'  length = 17 iobjnm = 'ZCLVISNO' ) )
      filtered   = VALUE #( ( iobjnm = 'ZCLSITE' rows = zzxxmla1_cl_bw_selection=>equals( `NORTH` )
                              sids = '/BIC/SZCLSITE' key_field = '/BIC/ZCLSITE' ) ) ).
    DATA(layout) = zzxxmla1_cl_bw_view_gen=>build_fact_layout( metadata ).
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_view_gen=>fact_ddl_source( provider = 'ZCLVISIT' view_name = 'ZZXXMLA1V0000091' layout = layout )
      exp = |@AbapCatalog.sqlViewName: 'ZZXXMLA1V0000091'{ nl }| &&
            |@AbapCatalog.compiler.compareFilter: true{ nl }| &&
            |@AccessControl.authorizationCheck: #NOT_REQUIRED{ nl }| &&
            |@EndUserText.label: 'BW provider ZCLVISIT: facts of ZCLSITE = NORTH'{ nl }| &&
            |define view ZZXXMLA1_C0000091{ nl }| &&
            |  as select from /bic/fzclvisit as a{ nl }| &&
            |    inner join /bic/szclsite as f1 on  f1.sid = a.sid_zclsite{ nl }| &&
            |\{{ nl }| &&
            |  a.sid_zclsite as SID_ZCLSITE,{ nl }| &&
            |  a.sid_zclroom as SID_ZCLROOM,{ nl }| &&
            |  a./bic/zclvisno as ZCLVISNO{ nl }| &&
            |\}{ nl }| &&
            |where f1./bic/zclsite = 'NORTH'{ nl }| ).
  ENDMETHOD.

  METHOD compounded_range.
    DATA(metadata) = VALUE ty_metadata(
      characteristic = '0FISCPER'
      tables         = VALUE #( basic = '0FISCPER' sids = '/BI0/SFISCPER' key_field = 'FISCPER' )
      sid_columns    = VALUE #( ( field = 'FISCVARNT' datatype = 'CHAR' length = 2 key = abap_true )
                                ( field = 'FISCPER'   datatype = 'NUMC' length = 7 key = abap_true )
                                ( field = 'SID'       datatype = 'INT4' length = 10 ) )
      compounding    = VALUE #( ( iobjnm = '0FISCVARNT' field = 'FISCVARNT' ) ) ).
    DATA(selection) = VALUE zzxxmla1_cl_bw_view_gen=>ty_t_selection(
      ( iobjnm = '0FISCPER' mode = zzxxmla1_cl_bw_selection=>c_mode-members
        rows   = VALUE #( ( sign = 'E' option = 'CP' low = `*014` ) ( sign = 'E' option = 'CP' low = `*013` ) ) )
      ( iobjnm = '0FISCVARNT' mode = zzxxmla1_cl_bw_selection=>c_mode-filter
        rows   = zzxxmla1_cl_bw_selection=>equals( `K4` ) ) ).
    DATA(layout) = zzxxmla1_cl_bw_view_gen=>build_layout( metadata = metadata selection = selection ).
    cl_abap_unit_assert=>assert_equals( act = layout-selection exp = `0FISCPER=E CP '*013',E CP '*014';0FISCVARNT=K4` ).
    cl_abap_unit_assert=>assert_equals(
      act = layout-filters
      exp = VALUE string_table( ( `s.fiscvarnt = 'K4'` )
                                ( `s.fiscper not like '%013' and s.fiscper not like '%014'` ) ) ).
    cl_abap_unit_assert=>assert_false( xsdbool( line_exists(
      layout-columns[ name = zzxxmla1_cl_bw_view_gen=>c_compound_key ] ) ) ).
    " the same view in the other mode
    selection[ iobjnm = '0FISCPER' ]-mode = zzxxmla1_cl_bw_selection=>c_mode-filter.
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_view_gen=>build_layout( metadata = metadata selection = selection )
      exp = layout ).
    " the label is a literal of the source: no quote in it
    DATA(source) = zzxxmla1_cl_bw_view_gen=>ddl_source( characteristic = '0FISCPER'
                                                        view_name      = 'ZZXXMLA1V0000013'
                                                        layout         = layout ).
    SPLIT source AT cl_abap_char_utilities=>newline INTO TABLE DATA(lines).
    cl_abap_unit_assert=>assert_char_cp( act = lines[ 4 ]
                                         exp = `@EndUserText.label: 'BW characteristic 0FISCPER: 0FISCPER = E CP *013*` ).
    cl_abap_unit_assert=>assert_equals( act = count( val = lines[ 4 ] sub = `'` ) exp = 2 ).
    cl_abap_unit_assert=>assert_char_cp(
      act = source
      exp = |*where s.fiscvarnt = 'K4'{ cl_abap_char_utilities=>newline }| &&
            |  and s.fiscper not like '%013' and s.fiscper not like '%014'{ cl_abap_char_utilities=>newline }| ).
  ENDMETHOD.

  METHOD compounding_two_values.
    DATA(metadata) = VALUE ty_metadata(
      characteristic = '0FISCPER'
      tables         = VALUE #( basic = '0FISCPER' sids = '/BI0/SFISCPER' key_field = 'FISCPER' )
      sid_columns    = VALUE #( ( field = 'FISCVARNT' datatype = 'CHAR' length = 2 key = abap_true )
                                ( field = 'FISCPER'   datatype = 'NUMC' length = 7 key = abap_true )
                                ( field = 'SID'       datatype = 'INT4' length = 10 ) )
      compounding    = VALUE #( ( iobjnm = '0FISCVARNT' field = 'FISCVARNT' ) ) ).
    DATA(layout) = zzxxmla1_cl_bw_view_gen=>build_layout(
      metadata  = metadata
      selection = VALUE #( ( iobjnm = '0FISCVARNT' mode = zzxxmla1_cl_bw_selection=>c_mode-filter
                             rows   = VALUE #( ( sign = 'I' option = 'EQ' low = `K4` )
                                               ( sign = 'I' option = 'EQ' low = `K1` ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = layout-selection exp = `0FISCVARNT=I EQ 'K1',I EQ 'K4'` ).
    cl_abap_unit_assert=>assert_equals(
      act = layout-filters
      exp = VALUE string_table( ( `( s.fiscvarnt = 'K1' or s.fiscvarnt = 'K4' )` ) ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists(
      layout-columns[ name = zzxxmla1_cl_bw_view_gen=>c_compound_key ] ) ) ).
  ENDMETHOD.

  METHOD fact_view_filter_mode.
    DATA(selection) = VALUE zzxxmla1_cl_bw_view_gen=>ty_t_selection(
      ( iobjnm = 'ZCLROOM' mode = zzxxmla1_cl_bw_selection=>c_mode-members
        rows   = VALUE #( ( sign = 'E' option = 'EQ' low = `R99` ) ) )
      ( iobjnm = 'ZCLSITE' mode = zzxxmla1_cl_bw_selection=>c_mode-filter
        rows   = VALUE #( ( sign = 'I' option = 'BT' low = `A` high = `M` ) ) ) ).
    DATA(filter) = zzxxmla1_cl_bw_view_gen=>filter_selection( selection ).
    cl_abap_unit_assert=>assert_equals( act = lines( filter ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = filter[ 1 ]-iobjnm exp = 'ZCLSITE' ).
    DATA(metadata) = fact_metadata_of_room( ).
    metadata-filtered = VALUE #( FOR f IN filter ( iobjnm = f-iobjnm rows = f-rows ) ).
    DATA(layout) = zzxxmla1_cl_bw_view_gen=>build_fact_layout( metadata ).
    cl_abap_unit_assert=>assert_equals( act = layout-filters
                                        exp = VALUE string_table( ( `a./bic/zclsite between 'A' and 'M'` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = layout-selection exp = `ZCLSITE=I BT 'A' 'M'` ).
    " restrict members only: the facts as they are, no fact view without a compounded characteristic
    metadata = fact_metadata_of_room( ).
    CLEAR metadata-compounded.
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_bw_view_gen=>filter_selection(
      VALUE #( ( selection[ iobjnm = 'ZCLROOM' ] ) ) ) ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_bw_view_gen=>build_fact_layout( metadata )-columns ).
  ENDMETHOD.

  METHOD selection_of_fixed.
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_view_gen=>selection_of( VALUE #( ( iobjnm = '0FISCVARNT' value = `K4` ) ) )
      exp = VALUE zzxxmla1_cl_bw_view_gen=>ty_t_selection(
              ( iobjnm = '0FISCVARNT' mode = zzxxmla1_cl_bw_selection=>c_mode-filter
                rows   = VALUE #( ( sign = 'I' option = 'EQ' low = `K4` ) ) ) ) ).
  ENDMETHOD.

  METHOD selection_text.
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_view_gen=>selection_text( VALUE #( ( iobjnm = '0VERSION' value = `000` )
                                                              ( iobjnm = '0FISCVARNT' value = `K4` ) ) )
      exp = `0FISCVARNT=K4;0VERSION=000` ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_bw_view_gen=>selection_text( VALUE #( ) ) ).
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
    DATA(fact) = zzxxmla1_cl_bw_view_gen=>fact_placeholder( 'ZCLVISITA' ).
    cl_abap_unit_assert=>assert_equals( act = fact exp = `ZZXXMLA1_F_ZCLVISITA` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_bw_view_gen=>provider_of_fact_placeholder( fact ) exp = `ZCLVISITA` ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_bw_view_gen=>characteristic_of_placeholder( fact ) ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_bw_view_gen=>provider_of_fact_placeholder( placeholder ) ).
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
