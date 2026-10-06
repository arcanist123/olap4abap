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
CLASS ltc_schema DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    "! cube, dimension usage of a shared dimension, attribute hierarchies, measures
    METHODS attribute_model FOR TESTING RAISING cx_static_check.
    "! Hierarchy elements before the attribute hierarchies, levels over source attributes or columns
    METHODS user_hierarchies FOR TESTING RAISING cx_static_check.
    "! a TimeDimension: level types on its levels, the reference's checks of them
    METHODS time_dimension FOR TESTING RAISING cx_static_check.
    "! what the engine cannot do yet is refused with a SOAP fault
    METHODS refused FOR TESTING.
    "! the server's catalog ZFOODMART gives the model the BW generator gave
    METHODS foodmart_catalog FOR TESTING RAISING cx_static_check.
    "! member properties of a level: the column and type of a sourceAttribute or their own; formatters and date types
    "! are refused
    METHODS properties FOR TESTING RAISING cx_static_check.
    "! an attribute keyed by the SID and named by the value (NameColumn): its hierarchy and a level over it
    METHODS name_column FOR TESTING RAISING cx_static_check.
    METHODS read
      IMPORTING xml           TYPE string
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_schema
      RAISING   zzxxmla1_cx_xmla.
ENDCLASS.

CLASS ltc_schema IMPLEMENTATION.

  METHOD read.
    result = zzxxmla1_cl_schema=>of_catalogs( VALUE #( ( name = `TEST` schema = xml updated_at = '20261004120000' ) ) ).
  ENDMETHOD.

  METHOD name_column.
    DATA(schema) = read(
      `<Schema name="S">` &&
      `  <Dimension name="Store" table="V_STORE">` &&
      `    <DimensionAttribute name="Store" usage="Key"><KeyColumn dataType="Integer" columnName="SID"/>` &&
      `      <NameColumn dataType="Numeric" columnName="STORE"/></DimensionAttribute>` &&
      `    <DimensionAttribute name="Country"><KeyColumn dataType="String" columnName="CNTRY"/></DimensionAttribute>` &&
      `    <Hierarchy name="Stores" hasAll="true"><Level name="Country" sourceAttribute="Country"/>` &&
      `      <Level name="Store" sourceAttribute="Store"/></Hierarchy>` &&
      `  </Dimension>` &&
      `  <Cube name="Sales"><Table name="/BIC/FSALES"/>` &&
      `    <DimensionUsage name="Store" source="Store" foreignKey="SID_STORE"/>` &&
      `    <Measure name="Units" column="UNITS" aggregator="sum"/></Cube>` &&
      `</Schema>` ).
    DATA(dimensions) = schema->dimensions( `Sales` ).
    cl_abap_unit_assert=>assert_equals( act = dimensions[ 1 ]-key_column exp = `SID` ).
    DATA(levels) = schema->levels( cube = `Sales` dim = `Store` hier = `Stores` ).
    DATA(level) = levels[ 2 ].
    cl_abap_unit_assert=>assert_equals( act = level-key_column exp = `SID` ).
    cl_abap_unit_assert=>assert_equals( act = level-name_column exp = `STORE` ).
    DATA(attribute) = schema->levels( cube = `Sales` dim = `Store` hier = `Store` ).
    cl_abap_unit_assert=>assert_equals( act = lines( attribute ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = attribute[ 1 ]-name_column exp = `STORE` ).
  ENDMETHOD.

  METHOD attribute_model.
    DATA(schema) = read(
      `<Schema name="S">` &&
      `  <Dimension name="Store" table="V_STORE">` &&
      `    <DimensionAttribute name="Store" usage="Key"><KeyColumn dataType="Integer" columnName="SID"/></DimensionAttribute>` &&
      `    <DimensionAttribute name="Country"><KeyColumn dataType="String" columnName="CNTRY"/></DimensionAttribute>` &&
      `    <DimensionAttribute name="Hidden" attributeHierarchyEnabled="false"><KeyColumn dataType="String" columnName="H"/></DimensionAttribute>` &&
      `    <DimensionAttribute name="Sqft"><KeyColumn dataType="Numeric" columnName="SQFT"/></DimensionAttribute>` &&
      `  </Dimension>` &&
      `  <Cube name="Sales" caption="The Sales">` &&
      `    <Table name="/BIC/FSALES"/>` &&
      `    <DimensionUsage name="Shop" source="Store" foreignKey="SID_STORE"/>` &&
      `    <Measure name="Units" column="UNITS" aggregator="sum" formatString="#,###"/>` &&
      `    <Measure name="Cost" column="COST" aggregator="sum" visible="false"/>` &&
      `  </Cube>` &&
      `</Schema>` ).
    cl_abap_unit_assert=>assert_equals( act = schema->catalogs( ) exp = VALUE string_table( ( `TEST` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = schema->cubes( ) exp = VALUE zzxxmla1_cl_schema=>ty_t_cube(
      ( cube_name = `Sales` catalog_name = `TEST` caption = `The Sales` fact_table = `/BIC/FSALES`
        generated_at = '20261004120000' ) ) ).
    cl_abap_unit_assert=>assert_equals( act = schema->dimensions( `Sales` ) exp = VALUE zzxxmla1_cl_schema=>ty_t_dim(
      ( cube_name = `Sales` dim_name = `Shop` seq_no = 1 caption = `Shop` fk_column = `SID_STORE` dim_table = `V_STORE`
        key_column = `SID` dim_type = `Standard` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = schema->hierarchies( cube = `Sales` dim = `Shop` )
                                        exp = VALUE zzxxmla1_cl_schema=>ty_t_hier(
      ( cube_name = `Sales` dim_name = `Shop` hier_name = `Store` name = `Shop.Store` seq_no = 1 caption = `Store` has_all = abap_true
        all_member_name = `All Shop.Stores` origin = 6 )
      ( cube_name = `Sales` dim_name = `Shop` hier_name = `Country` name = `Shop.Country` seq_no = 2 caption = `Country` has_all = abap_true
        all_member_name = `All Shop.Countrys` origin = 2 )
      ( cube_name = `Sales` dim_name = `Shop` hier_name = `Sqft` name = `Shop.Sqft` seq_no = 3 caption = `Sqft` has_all = abap_true
        all_member_name = `All Shop.Sqfts` origin = 2 ) ) ).
    cl_abap_unit_assert=>assert_equals( act = schema->levels( cube = `Sales` dim = `Shop` hier = `Sqft` )
                                        exp = VALUE zzxxmla1_cl_schema=>ty_t_level(
      ( cube_name = `Sales` dim_name = `Shop` hier_name = `Sqft` level_no = 1 level_name = `Sqft` caption = `Sqft`
        key_column = `SQFT` name_column = `SQFT` data_type = `Numeric` unique_members = abap_true
        level_type = `Regular` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = schema->measures( `Sales` ) exp = VALUE zzxxmla1_cl_schema=>ty_t_measure(
      ( cube_name = `Sales` meas_name = `Units` seq_no = 1 caption = `Units` fact_column = `UNITS` aggregator = `sum`
        format_string = `#,###` visible = abap_true )
      ( cube_name = `Sales` meas_name = `Cost` seq_no = 2 caption = `Cost` fact_column = `COST` aggregator = `sum`
        visible = abap_false ) ) ).
  ENDMETHOD.

  METHOD user_hierarchies.
    DATA(schema) = read(
      `<Schema name="S">` &&
      `  <Dimension name="Time" table="V_TIME">` &&
      `    <DimensionAttribute name="Time Id" usage="Key"><KeyColumn dataType="Integer" columnName="SID"/></DimensionAttribute>` &&
      `    <DimensionAttribute name="Year"><KeyColumn dataType="Numeric" columnName="YEAR"/></DimensionAttribute>` &&
      `    <DimensionAttribute name="Quarter"><KeyColumn dataType="String" columnName="QTR"/></DimensionAttribute>` &&
      `    <Hierarchy hasAll="false" defaultMember="[Time].[1997]">` &&
      `      <Level name="Year" uniqueMembers="true" sourceAttribute="Year"/>` &&
      `      <Level name="Quarter" sourceAttribute="Quarter"/>` &&
      `      <Level name="Day" column="DAY" nameColumn="DAYNAME" type="Numeric"/>` &&
      `    </Hierarchy>` &&
      `    <Hierarchy name="Fiscal" hasAll="true"><Level name="Year" sourceAttribute="Year"/></Hierarchy>` &&
      `  </Dimension>` &&
      `  <Cube name="Sales">` &&
      `    <Table name="F"/>` &&
      `    <DimensionUsage name="Time" source="Time" foreignKey="SID_TIME"/>` &&
      `    <Measure name="Units" column="UNITS" aggregator="sum"/>` &&
      `  </Cube>` &&
      `</Schema>` ).
    cl_abap_unit_assert=>assert_equals( act = schema->hierarchies( cube = `Sales` dim = `Time` )
                                        exp = VALUE zzxxmla1_cl_schema=>ty_t_hier(
      ( cube_name = `Sales` dim_name = `Time` hier_name = `Time` name = `Time` seq_no = 1 caption = `Time` has_all = abap_false
        all_member_name = `All Times` default_member = `[Time].[1997]` origin = 1 )
      ( cube_name = `Sales` dim_name = `Time` hier_name = `Fiscal` name = `Time.Fiscal` seq_no = 2 caption = `Fiscal` has_all = abap_true
        all_member_name = `All Time.Fiscals` origin = 1 )
      ( cube_name = `Sales` dim_name = `Time` hier_name = `Time Id` name = `Time.Time Id` seq_no = 3 caption = `Time Id` has_all = abap_true
        all_member_name = `All Time.Time Ids` origin = 6 )
      ( cube_name = `Sales` dim_name = `Time` hier_name = `Year` name = `Time.Year` seq_no = 4 caption = `Year` has_all = abap_true
        all_member_name = `All Time.Years` origin = 2 )
      ( cube_name = `Sales` dim_name = `Time` hier_name = `Quarter` name = `Time.Quarter` seq_no = 5 caption = `Quarter` has_all = abap_true
        all_member_name = `All Time.Quarters` origin = 2 ) ) ).
    cl_abap_unit_assert=>assert_equals( act = schema->levels( cube = `Sales` dim = `Time` hier = `Time` )
                                        exp = VALUE zzxxmla1_cl_schema=>ty_t_level(
      ( cube_name = `Sales` dim_name = `Time` hier_name = `Time` level_no = 1 level_name = `Year` caption = `Year`
        key_column = `YEAR` name_column = `YEAR` data_type = `Numeric` unique_members = abap_true level_type = `Regular` )
      ( cube_name = `Sales` dim_name = `Time` hier_name = `Time` level_no = 2 level_name = `Quarter` caption = `Quarter`
        key_column = `QTR` name_column = `QTR` data_type = `String` unique_members = abap_false level_type = `Regular` )
      ( cube_name = `Sales` dim_name = `Time` hier_name = `Time` level_no = 3 level_name = `Day` caption = `Day`
        key_column = `DAY` name_column = `DAYNAME` data_type = `Numeric` unique_members = abap_false
        level_type = `Regular` ) ) ).
  ENDMETHOD.

  METHOD time_dimension.
    DATA(attributes) =
      `<DimensionAttribute name="Time Id" usage="Key" levelType="TimeDays"><KeyColumn dataType="Integer" columnName="SID"/></DimensionAttribute>` &&
      `<DimensionAttribute name="Year" levelType="TimeYears"><KeyColumn dataType="Numeric" columnName="YEAR"/></DimensionAttribute>`.
    DATA(cube) = `<Cube name="C"><Table name="F"/><DimensionUsage name="Time" source="Time" foreignKey="X"/>` &&
                 `<Measure name="M" column="M" aggregator="sum"/></Cube>`.
    DATA(schema) = read( |<Schema name="S"><Dimension name="Time" type="TimeDimension" table="T">{ attributes }| &&
                         |<Hierarchy hasAll="false"><Level name="Year" sourceAttribute="Year" levelType="TimeYears"/>| &&
                         |<Level name="Half" column="H" levelType="TimeHalfYear"/></Hierarchy></Dimension>{ cube }</Schema>| ).
    DATA(dims) = schema->dimensions( `C` ).
    cl_abap_unit_assert=>assert_equals( act = dims[ 1 ]-dim_type exp = `Time` ).
    DATA(levels) = schema->levels( cube = `C` dim = `Time` hier = `Time` ).
    cl_abap_unit_assert=>assert_equals( act = levels[ 1 ]-level_type exp = `TimeYears` ).
    cl_abap_unit_assert=>assert_equals( act = levels[ 2 ]-level_type exp = `TimeHalfYears` ).
    levels = schema->levels( cube = `C` dim = `Time` hier = `Year` ).
    cl_abap_unit_assert=>assert_equals( act = levels[ 1 ]-level_type exp = `TimeYears` ).

    " without a type the first level decides (RolapDimension)
    schema = read( |<Schema name="S"><Dimension name="Time" table="T">{ attributes }</Dimension>{ cube }</Schema>| ).
    dims = schema->dimensions( `C` ).
    cl_abap_unit_assert=>assert_equals( act = dims[ 1 ]-dim_type exp = `Time` ).

    TRY.
        read( |<Schema name="S"><Dimension name="Time" type="TimeDimension" table="T">{ attributes }| &&
              |<DimensionAttribute name="Day Name"><KeyColumn dataType="String" columnName="D"/></DimensionAttribute>| &&
              |</Dimension>{ cube }</Schema>| ).
        cl_abap_unit_assert=>fail( `no fault` ).
      CATCH zzxxmla1_cx_xmla INTO DATA(fault).
        cl_abap_unit_assert=>assert_equals( act = fault->description
                                            exp = |olap4abap Error:Level '[Time.Day Name].[Day Name]' belongs to a time | &&
                                                  |hierarchy, so its level-type must be  'Years', 'Quarters', 'Months', | &&
                                                  |'Weeks' or 'Days'.| ).
    ENDTRY.
    TRY.
        read( |<Schema name="S"><Dimension name="Time" type="StandardDimension" table="T">{ attributes }| &&
              |</Dimension>{ cube }</Schema>| ).
        cl_abap_unit_assert=>fail( `no fault` ).
      CATCH zzxxmla1_cx_xmla INTO fault.
        cl_abap_unit_assert=>assert_equals( act = fault->description
                                            exp = |olap4abap Error:Level '[Time.Time Id].[Time Id]' does not belong to a | &&
                                                  |time hierarchy, so its level-type must be 'Standard'.| ).
    ENDTRY.
  ENDMETHOD.

  METHOD refused.
    DATA(dimension) = `<Dimension name="D" table="T">` &&
                      `<DimensionAttribute name="K" usage="Key"><KeyColumn dataType="Integer" columnName="SID"/></DimensionAttribute>`.
    DATA(cube) = `<Cube name="C"><Table name="F"/><DimensionUsage name="D" source="D" foreignKey="X"/>` &&
                 `<Measure name="M" column="M" aggregator="sum"/></Cube>`.
    TRY.
        read( |<Schema name="S">{ dimension }<Hierarchy hasAll="true"><Level name="L" column="c" parentColumn="p"/>| &&
              |</Hierarchy></Dimension>{ cube }</Schema>| ).
        cl_abap_unit_assert=>fail( `no fault` ).
      CATCH zzxxmla1_cx_xmla INTO DATA(fault).
        cl_abap_unit_assert=>assert_equals( act = fault->description
                                            exp = |olap4abap Error:Hierarchy 'D' of dimension 'D', level 'L': only a key | &&
                                                  |column and a name column of the dimension's table are supported| ).
    ENDTRY.
    TRY.
        read( |<Schema name="S">{ dimension }<Hierarchy hasAll="true"><Level name="L" sourceAttribute="X"/>| &&
              |</Hierarchy></Dimension>{ cube }</Schema>| ).
        cl_abap_unit_assert=>fail( `no fault` ).
      CATCH zzxxmla1_cx_xmla INTO fault.
        cl_abap_unit_assert=>assert_equals( act = fault->description
                                            exp = `olap4abap Error:sourceAttribute 'X' not found for level 'L'` ).
    ENDTRY.
    TRY.
        " an unnamed hierarchy and an attribute named like the dimension
        read( |<Schema name="S"><Dimension name="K" table="T">| &&
              |<DimensionAttribute name="K" usage="Key"><KeyColumn dataType="Integer" columnName="SID"/></DimensionAttribute>| &&
              |<Hierarchy hasAll="true"><Level name="L" sourceAttribute="K"/></Hierarchy></Dimension>| &&
              |<Cube name="C"><Table name="F"/><DimensionUsage name="K" source="K" foreignKey="X"/>| &&
              |<Measure name="M" column="M" aggregator="sum"/></Cube></Schema>| ).
        cl_abap_unit_assert=>fail( `no fault` ).
      CATCH zzxxmla1_cx_xmla INTO fault.
        cl_abap_unit_assert=>assert_equals( act = fault->description
                                            exp = |olap4abap Error:Dimension 'K': hierarchy 'K' is defined twice, by an | &&
                                                  |unnamed Hierarchy and by the attribute 'K'; name the Hierarchy| ).
    ENDTRY.
    TRY.
        read( `<Schema name="S"><Cube><Table name="F"/></Cube></Schema>` ).
        cl_abap_unit_assert=>fail( `no fault` ).
      CATCH zzxxmla1_cx_xmla INTO fault.
        cl_abap_unit_assert=>assert_equals( act = fault->description
                                            exp = |olap4abap Error:Error while loading catalog 'TEST': In Schema: In Cube: | &&
                                                  |Attribute 'name' is unset and has no default value.| ).
    ENDTRY.
  ENDMETHOD.

  METHOD foodmart_catalog.
    " the catalog as the server has it: datasources.xml and the schema file among the server's files
    DATA(schema) = zzxxmla1_cl_schema=>get( ).
    DATA(cubes) = schema->cubes( ).
    cl_abap_unit_assert=>assert_equals( act = cubes[ 1 ]-cube_name exp = `ZFMSALES` ).
    DATA(dims) = schema->dimensions( `ZFMSALES` ).
    cl_abap_unit_assert=>assert_equals( act = lines( dims ) exp = 5 ).
    cl_abap_unit_assert=>assert_equals( act = dims[ 3 ]-dim_table exp = `ZZXXMLA1V0000003` ).
    cl_abap_unit_assert=>assert_equals( act = dims[ 5 ]-dim_type exp = `Time` ).
    cl_abap_unit_assert=>assert_equals( act = dims[ 1 ]-dim_type exp = `Standard` ).
    DATA(count) = 0.
    LOOP AT dims INTO DATA(dim).
      count = count + lines( schema->hierarchies( cube = `ZFMSALES` dim = dim-dim_name ) ).
    ENDLOOP.
    " as the reference server lists them in MDSCHEMA_HIERARCHIES (reference/mdschema_hierarchies: 48 and [Measures])
    cl_abap_unit_assert=>assert_equals( act = count exp = 48 ).
    DATA(store_hierarchies) = schema->hierarchies( cube = `ZFMSALES` dim = `Store` ).
    cl_abap_unit_assert=>assert_equals( act = store_hierarchies[ 1 ]-hier_name exp = `Store` ).
    cl_abap_unit_assert=>assert_equals( act = lines( schema->levels( cube = `ZFMSALES` dim = `Product` hier = `Product` ) )
                                        exp = 6 ).
    cl_abap_unit_assert=>assert_equals( act = lines( schema->measures( `ZFMSALES` ) ) exp = 3 ).
    DATA(store_levels) = schema->levels( cube = `ZFMSALES` dim = `Store` hier = `Store` ).
    cl_abap_unit_assert=>assert_equals( act = lines( store_levels[ 4 ]-properties ) exp = 8 ).
    cl_abap_unit_assert=>assert_equals( act = store_levels[ 4 ]-properties[ 3 ]
                                        exp = VALUE zzxxmla1_cl_schema=>ty_property(
                                          name = `Store Sqft` caption = `Store Sqft` column = `ZFMSQFT`
                                          data_type = `Numeric` ) ).
  ENDMETHOD.

  METHOD properties.
    DATA(head) = `<Schema name="S"><Dimension name="D" table="T">` &&
                 `<DimensionAttribute name="K" usage="Key"><KeyColumn dataType="Integer" columnName="SID"/></DimensionAttribute>` &&
                 `<DimensionAttribute name="A"><KeyColumn dataType="Numeric" columnName="COL_A"/></DimensionAttribute>` &&
                 `<Hierarchy hasAll="true"><Level name="L" sourceAttribute="K">`.
    DATA(tail) = `</Level></Hierarchy></Dimension>` &&
                 `<Cube name="C"><Table name="F"/><DimensionUsage name="D" source="D" foreignKey="X"/>` &&
                 `<Measure name="M" column="M" aggregator="sum"/></Cube></Schema>`.
    DATA(schema) = read( head && `<Property name="P1" sourceAttribute="A" type="String"/>` &&
                         `<Property name="P2" column="COL_B" caption="Second"/>` &&
                         `<Property name="P3" column="COL_C" type="Boolean"/>` && tail ).
    DATA(levels) = schema->levels( cube = `C` dim = `D` hier = `D` ).
    cl_abap_unit_assert=>assert_equals(
      act = levels[ 1 ]-properties
      exp = VALUE zzxxmla1_cl_schema=>ty_t_property(
        ( name = `P1` caption = `P1` column = `COL_A` data_type = `Numeric` )
        ( name = `P2` caption = `Second` column = `COL_B` data_type = `String` )
        ( name = `P3` caption = `P3` column = `COL_C` data_type = `Boolean` ) ) ).
    TRY.
        read( head && `<Property name="P" column="COL_D" type="Date"/>` && tail ).
        cl_abap_unit_assert=>fail( `no fault` ).
      CATCH zzxxmla1_cx_xmla INTO DATA(fault).
        cl_abap_unit_assert=>assert_equals( act = fault->description
                                            exp = |olap4abap Error:Hierarchy 'D' of dimension 'D', level 'L', | &&
                                                  |property 'P': the type Date is not supported| ).
    ENDTRY.
    TRY.
        read( head && `<Property name="P" sourceAttribute="X"/>` && tail ).
        cl_abap_unit_assert=>fail( `no fault` ).
      CATCH zzxxmla1_cx_xmla INTO fault.
        cl_abap_unit_assert=>assert_equals( act = fault->description
                                            exp = `olap4abap Error:sourceAttribute 'X' not found for property 'P' of level 'L'` ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
