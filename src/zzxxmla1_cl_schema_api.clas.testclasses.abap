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
"! The API's routing and the parts of accept that change nothing; one test checks the real ZFMSALES proposal against
"! the server's catalogs (refused before anything is written).
CLASS ltc_api DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    DATA api TYPE REF TO zzxxmla1_cl_schema_api.

    METHODS setup.
    "! a data sources file with the catalog ZFOODMART
    METHODS datasources
      RETURNING VALUE(result) TYPE string.
    "! a schema with a shared dimension on a DDL source and a private one on a view
    METHODS schema_xml
      RETURNING VALUE(result) TYPE string.
    METHODS unknown_resource FOR TESTING.
    METHODS wrong_method FOR TESTING.
    METHODS json_escapes FOR TESTING.
    METHODS catalog_added FOR TESTING RAISING cx_static_check.
    METHODS catalog_already_there FOR TESTING RAISING cx_static_check.
    METHODS catalog_of_another_file FOR TESTING.
    METHODS catalog_names FOR TESTING.
    METHODS tables_mapped FOR TESTING RAISING cx_static_check.
    METHODS outline FOR TESTING RAISING cx_static_check.
    METHODS accept_unreadable_schema FOR TESTING.
    METHODS proposal_needs_provider FOR TESTING.
    METHODS providers FOR TESTING.
    METHODS accept_checks_all_catalogs FOR TESTING RAISING cx_static_check.
    METHODS check_needs_post FOR TESTING.
    METHODS first_catalogs FOR TESTING RAISING cx_static_check.
    METHODS timestamps FOR TESTING.
    METHODS schemas FOR TESTING.
    METHODS schema_of_catalog FOR TESTING.
    METHODS schema_errors FOR TESTING.
    METHODS catalog_removed FOR TESTING RAISING cx_static_check.
    METHODS last_catalog_removed FOR TESTING RAISING cx_static_check.
    METHODS catalog_removed_inline FOR TESTING RAISING cx_static_check.
    METHODS remove_unknown_catalog FOR TESTING.
    METHODS remove_errors FOR TESTING.
ENDCLASS.

CLASS zzxxmla1_cl_schema_api DEFINITION LOCAL FRIENDS ltc_api.

CLASS ltc_api IMPLEMENTATION.

  METHOD setup.
    api = NEW #( ).
  ENDMETHOD.

  METHOD datasources.
    result =
      |<?xml version="1.0"?>\n<DataSources>\n  <DataSource>\n    <DataSourceName>A</DataSourceName>\n| &&
      |    <DataSourceDescription>a</DataSourceDescription>\n    <URL></URL>\n| &&
      |    <DataSourceInfo>Provider=olap4abap</DataSourceInfo>\n    <ProviderName>olap4abap</ProviderName>\n| &&
      |    <ProviderType>MDP</ProviderType>\n    <AuthenticationMode>Unauthenticated</AuthenticationMode>\n| &&
      |    <Catalogs>\n      <Catalog name="ZFOODMART">\n        <Definition>/WEB-INF/schema/FoodmartBW.xml</Definition>\n| &&
      |      </Catalog>\n    </Catalogs>\n  </DataSource>\n</DataSources>\n|.
  ENDMETHOD.

  METHOD schema_xml.
    result =
      `<Schema name="S">` &&
      `<Dimension name="Store" table="ZZXXMLA1_C_ZFMSTORE">` &&
      `<DimensionAttribute name="Store" usage="Key"><KeyColumn dataType="Integer" columnName="SID"/></DimensionAttribute>` &&
      `</Dimension>` &&
      `<Cube name="C">` &&
      `<Table name="/BIC/FZFMSALES"/>` &&
      `<DimensionUsage name="Store" source="Store" foreignKey="SID_ZFMSTORE"/>` &&
      `<Dimension name="Promotion" table="ZZXXMLA1V0000004" foreignKey="SID_ZFMPROMO">` &&
      `<DimensionAttribute name="Promotion" usage="Key"><KeyColumn dataType="Integer" columnName="SID"/></DimensionAttribute>` &&
      `</Dimension>` &&
      `<Measure name="Unit Sales" column="ZFMUNITS" aggregator="sum"/>` &&
      `</Cube>` &&
      `</Schema>`.
  ENDMETHOD.

  METHOD unknown_resource.
    DATA(result) = api->handle( VALUE #( method = `GET` path = `/schema/api/nothing` ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 404 ).
    cl_abap_unit_assert=>assert_equals( act = result-body exp = `{"error":"No resource /schema/api/nothing"}` ).
    cl_abap_unit_assert=>assert_true( zzxxmla1_cl_schema_api=>is_api( `/schema/api/providers` ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_schema_api=>is_api( `` ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_schema_api=>is_api( `/schema/apix` ) ).
  ENDMETHOD.

  METHOD wrong_method.
    DATA(result) = api->handle( VALUE #( method = `GET` path = `/schema/api/accept` ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 405 ).
    cl_abap_unit_assert=>assert_equals( act = result-allow exp = `POST` ).
  ENDMETHOD.

  METHOD json_escapes.
    cl_abap_unit_assert=>assert_equals( act = api->json( |a"b\\c\nd| ) exp = `"a\"b\\c\nd"` ).
    cl_abap_unit_assert=>assert_equals( act = api->json_array( VALUE #( ( `1` ) ( `"x"` ) ) ) exp = `[1,"x"]` ).
    cl_abap_unit_assert=>assert_equals( act = api->json_array( VALUE #( ) ) exp = `[]` ).
  ENDMETHOD.

  METHOD catalog_added.
    DATA(result) = api->add_catalog( content = datasources( ) catalog = `ZFMSALESA` definition = `/WEB-INF/schema/ZFMSALESA.xml` ).
    DATA(catalogs) = zzxxmla1_cl_repository=>of_content( result )->data_sources( ).
    DATA(first) = catalogs[ 1 ].
    cl_abap_unit_assert=>assert_equals( act = lines( first-catalogs ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = first-catalogs[ 2 ]
                                        exp = VALUE zzxxmla1_cl_repository=>ty_catalog(
                                                name = `ZFMSALESA` definition = `/WEB-INF/schema/ZFMSALESA.xml` ) ).
    " indented as the file is, the rest unchanged
    cl_abap_unit_assert=>assert_char_cp( act = result
      exp = |*      </Catalog>\n      <Catalog name="ZFMSALESA">\n        <Definition>/WEB-INF/schema/ZFMSALESA.xml| &&
            |</Definition>\n      </Catalog>\n    </Catalogs>\n  </DataSource>\n</DataSources>\n| ).
  ENDMETHOD.

  METHOD catalog_already_there.
    cl_abap_unit_assert=>assert_equals(
      act = api->add_catalog( content = datasources( ) catalog = `ZFOODMART` definition = `/WEB-INF/schema/FoodmartBW.xml` )
      exp = datasources( ) ).
  ENDMETHOD.

  METHOD catalog_of_another_file.
    TRY.
        api->add_catalog( content = datasources( ) catalog = `ZFOODMART` definition = `/WEB-INF/schema/ZFOODMART.xml` ).
        cl_abap_unit_assert=>fail( `refused expected` ).
      CATCH zzxxmla1_cx_api_refused INTO DATA(refused).
        cl_abap_unit_assert=>assert_equals( act = refused->status exp = 400 ).
        cl_abap_unit_assert=>assert_equals(
          act = refused->message
          exp = `Catalog 'ZFOODMART' exists already, with the schema file /WEB-INF/schema/FoodmartBW.xml` ).
    ENDTRY.
  ENDMETHOD.

  METHOD catalog_names.
    TRY.
        api->check_catalog_name( `ZFMSALES_2.v-1` ).
      CATCH zzxxmla1_cx_api_refused.
        cl_abap_unit_assert=>fail( `ZFMSALES_2.v-1 is a valid name` ).
    ENDTRY.
    LOOP AT VALUE string_table( ( `../x` ) ( `.x` ) ( `a b` ) ( `a/b` ) ) INTO DATA(name).
      TRY.
          api->check_catalog_name( name ).
          cl_abap_unit_assert=>fail( |{ name } must be refused| ).
        CATCH zzxxmla1_cx_api_refused ##NO_HANDLER.
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

  METHOD tables_mapped.
    DATA(schema) = zzxxmla1_cl_schema_def=>parse( schema_xml( ) ).
    DATA(names) = api->map_tables( CHANGING schema = schema ).
    cl_abap_unit_assert=>assert_equals( act = names exp = VALUE string_table( ( `ZZXXMLA1_C_ZFMSTORE` ) ( `ZZXXMLA1V0000004` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = api->characteristic_of( names[ 1 ] ) exp = `ZFMSTORE` ).
    cl_abap_unit_assert=>assert_initial( api->characteristic_of( names[ 2 ] ) ).

    api->map_tables( EXPORTING views  = VALUE #( ( characteristic = 'ZFMSTORE' ddl_name = 'ZZXXMLA1_C_ZFMSTORE'
                                                   view_name = 'ZZXXMLA1V0000003' ) )
                     CHANGING  schema = schema ).
    cl_abap_unit_assert=>assert_equals( act = schema-dimensions[ 1 ]-table exp = `ZZXXMLA1V0000003` ).
    DATA(xml) = zzxxmla1_cl_schema_def=>to_xml( schema ).
    cl_abap_unit_assert=>assert_char_cp( act = xml exp = `*table="ZZXXMLA1V0000003"*table="ZZXXMLA1V0000004"*` ).
  ENDMETHOD.

  METHOD outline.
    DATA(outline) = api->outline( zzxxmla1_cl_schema_def=>parse( schema_xml( ) ) ).
    cl_abap_unit_assert=>assert_char_cp(
      act = outline
      exp = `{"name":"S","dimensions":[{"name":"Store",*"table":"ZZXXMLA1_C_ZFMSTORE","attributes":[{"name":"Store",` &&
            `"usage":"Key","keyColumn":"SID","nameColumn":"",*"hierarchies":[]}],"cubes":[{"name":"C",*` &&
            `"factTable":"/BIC/FZFMSALES",*"dimensions":[{"name":"Store","source":"Store","foreignKey":"SID_ZFMSTORE"},` &&
            `{"name":"Promotion","foreignKey":"SID_ZFMPROMO","dimension":{"name":"Promotion",*}}],` &&
            `"measures":[{"name":"Unit Sales","column":"ZFMUNITS","aggregator":"sum",*}]}]}` ).
  ENDMETHOD.

  METHOD accept_unreadable_schema.
    DATA(result) = api->handle( VALUE #( method = `POST` path = `/schema/api/accept` body = `<Schema>` ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 400 ).
    cl_abap_unit_assert=>assert_char_cp( act = result-body exp = `{"error":"Schema not readable: *` ).
  ENDMETHOD.

  METHOD proposal_needs_provider.
    DATA(result) = api->handle( VALUE #( method = `GET` path = `/schema/api/proposal` ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 400 ).
    cl_abap_unit_assert=>assert_equals( act = result-body exp = `{"error":"Parameter provider is missing"}` ).
  ENDMETHOD.

  METHOD providers.
    DATA(result) = api->handle( VALUE #( method = `GET` path = `/schema/api/providers` ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 200 ).
    cl_abap_unit_assert=>assert_char_cp( act = result-body exp = `{"providers":[*{"name":"ZFMSALES","kind":"InfoCube",*` ).
  ENDMETHOD.

  METHOD accept_checks_all_catalogs.
    " the ZFMSALES proposal has the cube ZFMSALES, which the server's catalog ZFOODMART has already
    DATA(proposal) = api->handle( VALUE #( method = `GET` path = `/schema/api/proposal`
                                           parameters = VALUE #( ( name = `provider` value = `ZFMSALES` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = proposal-status exp = 200 ).
    DATA(proposed) = NEW zzxxmla1_cl_schema_proposal( )->propose( NEW zzxxmla1_cl_bw_provider( )->read( `ZFMSALES` ) ).
    DATA(xml) = proposed-xml.
    DATA(result) = api->handle( VALUE #( method = `POST` path = `/schema/api/accept` body = xml
                                         parameters = VALUE #( ( name = `catalog` value = `ZZXXMLA1_UNIT_TEST` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 400 ).
    cl_abap_unit_assert=>assert_char_cp( act = result-body exp = `*Cube 'ZFMSALES' is defined twice*` ).
    DATA(file) = zzxxmla1_cl_files=>read( `/WEB-INF/schema/ZZXXMLA1_UNIT_TEST.xml` ).
    cl_abap_unit_assert=>assert_initial( file-path ).
    " check answers as accept does
    result = api->handle( VALUE #( method = `POST` path = `/schema/api/check` body = xml
                                   parameters = VALUE #( ( name = `catalog` value = `ZZXXMLA1_UNIT_TEST` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 400 ).
    cl_abap_unit_assert=>assert_char_cp( act = result-body exp = `*Cube 'ZFMSALES' is defined twice*` ).
  ENDMETHOD.

  METHOD check_needs_post.
    DATA(result) = api->handle( VALUE #( method = `GET` path = `/schema/api/check` ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 405 ).
    cl_abap_unit_assert=>assert_equals( act = result-allow exp = `POST` ).
    result = api->handle( VALUE #( method = `POST` path = `/schema/api/schemas` ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 405 ).
    cl_abap_unit_assert=>assert_equals( act = result-allow exp = `GET` ).
  ENDMETHOD.

  METHOD first_catalogs.
    " a second data source with ZFOODMART on another file and a catalog of its own
    DATA(content) = replace( val = datasources( ) sub = `</DataSources>`
      with = |<DataSource><DataSourceName>B</DataSourceName><DataSourceDescription>b</DataSourceDescription>| &&
             |<URL></URL><DataSourceInfo>Provider=olap4abap</DataSourceInfo><ProviderName>olap4abap</ProviderName>| &&
             |<ProviderType>MDP</ProviderType><AuthenticationMode>Unauthenticated</AuthenticationMode>| &&
             |<Catalogs><Catalog name="ZFOODMART"><Definition>/WEB-INF/schema/Other.xml</Definition></Catalog>| &&
             |<Catalog name="X"><Definition>/WEB-INF/schema/X.xml</Definition></Catalog></Catalogs>| &&
             |</DataSource></DataSources>| ).
    cl_abap_unit_assert=>assert_equals(
      act = api->first_catalogs( content )
      exp = VALUE zzxxmla1_cl_schema_api=>ty_t_catalog_entry(
              ( data_source = `A` name = `ZFOODMART` definition = `/WEB-INF/schema/FoodmartBW.xml` )
              ( data_source = `B` name = `X` definition = `/WEB-INF/schema/X.xml` ) ) ).
  ENDMETHOD.

  METHOD timestamps.
    cl_abap_unit_assert=>assert_equals( act = api->json_timestamp( '20261006123456.4000000' )
                                        exp = `"2026-10-06T12:34:56Z"` ).
    cl_abap_unit_assert=>assert_equals( act = api->json_timestamp( 0 ) exp = `null` ).
  ENDMETHOD.

  METHOD schemas.
    DATA(result) = api->handle( VALUE #( method = `GET` path = `/schema/api/schemas` ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 200 ).
    cl_abap_unit_assert=>assert_char_cp( act = result-body
      exp = `{"schemas":[*{"catalog":"ZFOODMART","dataSource":"*","file":"/WEB-INF/schema/FoodmartBW.xml","exists":true,*` ).
  ENDMETHOD.

  METHOD schema_of_catalog.
    DATA(result) = api->handle( VALUE #( method = `GET` path = `/schema/api/schema`
                                         parameters = VALUE #( ( name = `catalog` value = `ZFOODMART` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 200 ).
    cl_abap_unit_assert=>assert_char_cp( act = result-body
      exp = `{"catalog":"ZFOODMART",*"file":"/WEB-INF/schema/FoodmartBW.xml",*"xml":"*<Schema*","outline":{"name":*` ).
  ENDMETHOD.

  METHOD schema_errors.
    DATA(result) = api->handle( VALUE #( method = `GET` path = `/schema/api/schema` ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 400 ).
    cl_abap_unit_assert=>assert_equals( act = result-body exp = `{"error":"Parameter catalog is missing"}` ).
    result = api->handle( VALUE #( method = `GET` path = `/schema/api/schema`
                                   parameters = VALUE #( ( name = `catalog` value = `NO_SUCH_CATALOG` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 404 ).
    cl_abap_unit_assert=>assert_equals( act = result-body exp = `{"error":"No catalog 'NO_SUCH_CATALOG'"}` ).
  ENDMETHOD.

  METHOD catalog_removed.
    " what add_catalog adds, remove_catalog takes away, line by line
    DATA(added) = api->add_catalog( content = datasources( ) catalog = `ZFMSALESA` definition = `/WEB-INF/schema/ZFMSALESA.xml` ).
    cl_abap_unit_assert=>assert_equals( act = api->remove_catalog( content = added catalog = `ZFMSALESA` )
                                        exp = datasources( ) ).
  ENDMETHOD.

  METHOD last_catalog_removed.
    DATA(result) = api->remove_catalog( content = datasources( ) catalog = `ZFOODMART` ).
    cl_abap_unit_assert=>assert_char_cp( act = result
      exp = |*<AuthenticationMode>Unauthenticated</AuthenticationMode>\n    <Catalogs>\n    </Catalogs>\n  </DataSource>*| ).
    DATA(data_sources) = zzxxmla1_cl_repository=>of_content( result )->data_sources( ).
    cl_abap_unit_assert=>assert_initial( data_sources[ 1 ]-catalogs ).
  ENDMETHOD.

  METHOD catalog_removed_inline.
    " on one line with other elements, in every data source, single quotes
    DATA(content) = replace( val = datasources( ) sub = `</DataSources>`
      with = |<DataSource><DataSourceName>B</DataSourceName><DataSourceDescription>b</DataSourceDescription>| &&
             |<URL></URL><DataSourceInfo>Provider=olap4abap</DataSourceInfo><ProviderName>olap4abap</ProviderName>| &&
             |<ProviderType>MDP</ProviderType><AuthenticationMode>Unauthenticated</AuthenticationMode>| &&
             |<Catalogs><Catalog name='ZFOODMART'><Definition>/WEB-INF/schema/FoodmartBW.xml</Definition></Catalog>| &&
             |<Catalog name="X"><Definition>/WEB-INF/schema/X.xml</Definition></Catalog></Catalogs>| &&
             |</DataSource></DataSources>| ).
    DATA(result) = api->remove_catalog( content = content catalog = `ZFOODMART` ).
    cl_abap_unit_assert=>assert_equals(
      act = api->all_catalogs( result )
      exp = VALUE zzxxmla1_cl_schema_api=>ty_t_catalog_entry(
              ( data_source = `B` name = `X` definition = `/WEB-INF/schema/X.xml` ) ) ).
    cl_abap_unit_assert=>assert_char_cp( act = result
      exp = |*<Catalogs><Catalog name="X"><Definition>/WEB-INF/schema/X.xml</Definition></Catalog></Catalogs>*| ).
  ENDMETHOD.

  METHOD remove_unknown_catalog.
    TRY.
        api->remove_catalog( content = datasources( ) catalog = `ZFOOD` ).
        cl_abap_unit_assert=>fail( `refused expected` ).
      CATCH zzxxmla1_cx_api_refused INTO DATA(refused).
        cl_abap_unit_assert=>assert_equals( act = refused->status exp = 404 ).
        cl_abap_unit_assert=>assert_equals( act = refused->message exp = `No catalog 'ZFOOD'` ).
    ENDTRY.
  ENDMETHOD.

  METHOD remove_errors.
    DATA(result) = api->handle( VALUE #( method = `GET` path = `/schema/api/remove` ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 405 ).
    cl_abap_unit_assert=>assert_equals( act = result-allow exp = `POST` ).
    result = api->handle( VALUE #( method = `POST` path = `/schema/api/remove` ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 400 ).
    cl_abap_unit_assert=>assert_equals( act = result-body exp = `{"error":"Parameter catalog is missing"}` ).
    result = api->handle( VALUE #( method = `POST` path = `/schema/api/remove`
                                   parameters = VALUE #( ( name = `catalog` value = `NO_SUCH_CATALOG` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = result-status exp = 404 ).
    cl_abap_unit_assert=>assert_equals( act = result-body exp = `{"error":"No catalog 'NO_SUCH_CATALOG'"}` ).
  ENDMETHOD.

ENDCLASS.