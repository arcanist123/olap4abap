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
CLASS ltc_repository DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    "! the data sources and their catalogs as DataSourcesConfig reads them
    METHODS data_sources FOR TESTING RAISING cx_static_check.
    "! the data source of a DataSourceInfo property (FileRepository.getConnection)
    METHODS data_source FOR TESTING RAISING cx_static_check.
    "! DISCOVER_DATASOURCES's DataSourceInfo: without Jdbc, JdbcUser and JdbcPassword
    METHODS public_data_source_info FOR TESTING RAISING cx_static_check.
    "! Util.parseConnectString and PropertyList.toString
    METHODS connect_strings FOR TESTING RAISING cx_static_check.
    "! errors with the reference's messages
    METHODS errors FOR TESTING.
    METHODS file
      RETURNING VALUE(result) TYPE string.
ENDCLASS.

CLASS ltc_repository IMPLEMENTATION.

  METHOD file.
    result =
      `<?xml version="1.0"?>` &&
      `<DataSources>` &&
      `  <DataSource>` &&
      `    <DataSourceName>ABAP BW</DataSourceName>` &&
      `    <DataSourceDescription> BW cubes </DataSourceDescription>` &&
      `    <URL>http://localhost:50000/zzxxmla1</URL>` &&
      `    <DataSourceInfo>Provider=olap4abap;Jdbc=jdbc:hsqldb:res:/foodmart;JdbcDrivers=org.hsqldb.jdbc.JDBCDriver</DataSourceInfo>` &&
      `    <ProviderName>olap4abap</ProviderName>` &&
      `    <ProviderType>MDP</ProviderType>` &&
      `    <AuthenticationMode>Unauthenticated</AuthenticationMode>` &&
      `    <Catalogs>` &&
      `      <Catalog name="ZFOODMART"><Definition>/WEB-INF/schema/FoodmartBW.xml</Definition></Catalog>` &&
      `      <Catalog name="OTHER"><DataSourceInfo>Provider=olap4abap</DataSourceInfo>` &&
      `        <Definition>/WEB-INF/schema/Other.xml</Definition></Catalog>` &&
      `    </Catalogs>` &&
      `  </DataSource>` &&
      `  <DataSource>` &&
      `    <DataSourceName>Second</DataSourceName>` &&
      `    <DataSourceDescription/>` &&
      `    <URL/>` &&
      `    <DataSourceInfo>Provider=olap4abap</DataSourceInfo>` &&
      `    <ProviderName>olap4abap</ProviderName>` &&
      `    <ProviderType>MDP</ProviderType>` &&
      `    <AuthenticationMode>Unauthenticated</AuthenticationMode>` &&
      `    <Catalogs/>` &&
      `  </DataSource>` &&
      `</DataSources>`.
  ENDMETHOD.

  METHOD data_sources.
    DATA(data_sources) = zzxxmla1_cl_repository=>of_content( file( ) )->data_sources( ).
    cl_abap_unit_assert=>assert_equals( act = lines( data_sources ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals(
      act = data_sources[ 1 ]
      exp = VALUE zzxxmla1_cl_repository=>ty_data_source(
        name                = `ABAP BW`
        description         = `BW cubes`
        url                 = `http://localhost:50000/zzxxmla1`
        data_source_info    = `Provider=olap4abap;Jdbc=jdbc:hsqldb:res:/foodmart;JdbcDrivers=org.hsqldb.jdbc.JDBCDriver`
        provider_name       = `olap4abap`
        provider_type       = `MDP`
        authentication_mode = `Unauthenticated`
        catalogs            = VALUE #(
          ( name = `ZFOODMART` definition = `/WEB-INF/schema/FoodmartBW.xml` )
          ( name = `OTHER` data_source_info = `Provider=olap4abap` definition = `/WEB-INF/schema/Other.xml` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = data_sources[ 2 ]-name exp = `Second` ).
    cl_abap_unit_assert=>assert_initial( data_sources[ 2 ]-catalogs ).
  ENDMETHOD.

  METHOD data_source.
    DATA(repository) = zzxxmla1_cl_repository=>of_content( file( ) ).
    cl_abap_unit_assert=>assert_equals( act = repository->data_source( `` )-name exp = `ABAP BW` ).
    cl_abap_unit_assert=>assert_equals( act = repository->data_source( `Second` )-name exp = `Second` ).
    " the connect string without the logon to the database, as the reference writes it
    cl_abap_unit_assert=>assert_equals(
      act = repository->data_source( `Provider=olap4abap; JdbcDrivers=org.hsqldb.jdbc.JDBCDriver` )-name
      exp = `ABAP BW` ).
    cl_abap_unit_assert=>assert_initial( repository->data_source( `Unknown` ) ).
  ENDMETHOD.

  METHOD public_data_source_info.
    " as the reference server answers DISCOVER_DATASOURCES (reference/discover_datasources)
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_repository=>public_data_source_info(
              `Provider=olap4abap;Jdbc=jdbc:hsqldb:res:/hsqldb-foodmart/foodmart;JdbcDrivers=org.hsqldb.jdbc.JDBCDriver` )
      exp = `Provider=olap4abap; JdbcDrivers=org.hsqldb.jdbc.JDBCDriver` ).
    " nothing removed: as written
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_repository=>public_data_source_info( `Provider=olap4abap;x=1` )
                                        exp = `Provider=olap4abap;x=1` ).
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_repository=>public_data_source_info( `jdbcuser=u; JDBCPASSWORD=p; Catalog=c` )
      exp = `Catalog=c` ).
  ENDMETHOD.

  METHOD connect_strings.
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_repository=>parse_connect_string(
              ` Provider = olap4abap ; Jdbc='a;b' ; x="it""s" ; a==b=1;empty=;Provider=other; last` )
      exp = VALUE zzxxmla1_cl_repository=>ty_t_property(
        ( name = `Provider` value = `olap4abap` )
        ( name = `Jdbc` value = `a;b` )
        ( name = `x` value = `it"s` )
        ( name = `a=b` value = `1` )
        ( name = `empty` value = `` )
        ( name = `last` value = `` ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_repository=>connect_string( VALUE #( ( name = `Provider` value = `olap4abap` )
                                                             ( name = `Jdbc` value = `it's;b` )
                                                             ( name = `Q` value = `'x;y'` ) ) )
      " a value already in quotes gets no more, but its quotes are doubled (REVIEW note)
      exp = `Provider=olap4abap; Jdbc='it''s;b'; Q=''x;y''` ).
  ENDMETHOD.

  METHOD errors.
    TRY.
        zzxxmla1_cl_repository=>of_content(
          `<DataSources><DataSource><DataSourceName>A</DataSourceName><URL/></DataSource></DataSources>` ).
        cl_abap_unit_assert=>fail( `no fault` ).
      CATCH zzxxmla1_cx_xmla INTO DATA(fault).
        cl_abap_unit_assert=>assert_equals(
          act = fault->description
          exp = |olap4abap Error:Internal error: Failed to parse data sources config /WEB-INF/datasources.xml: | &&
                |In DataSources: In DataSource: Expected <DataSourceDescription> but found <URL>| ).
    ENDTRY.
    TRY.
        zzxxmla1_cl_repository=>of_content( replace( val = file( ) sub = `name="OTHER"` with = `name="ZFOODMART"` ) ).
        cl_abap_unit_assert=>fail( `no fault` ).
      CATCH zzxxmla1_cx_xmla INTO fault.
        cl_abap_unit_assert=>assert_equals(
          act = fault->description
          exp = `olap4abap Error:Internal error: more than one DataSource object has name 'ZFOODMART'` ).
    ENDTRY.
    TRY.
        zzxxmla1_cl_repository=>parse_connect_string( `a='b` ).
        cl_abap_unit_assert=>fail( `no fault` ).
      CATCH zzxxmla1_cx_xmla INTO fault.
        cl_abap_unit_assert=>assert_equals(
          act = fault->description
          exp = `olap4abap Error:Internal error: Connect string 'a='b' contains unterminated quoted value 'b'` ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
