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
CLASS zzxxmla1_cl_xmla_rowsets DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    " The rowsets (request types) of XML for Analysis, as the reference lists them (xmla.RowsetDefinition). Static
    " knowledge of the engine, not read from the model tables. Restrictions are written "NAME:type NAME:type ...", the
    " type being the XML schema type without the xsd: prefix. Columns (all columns of the rowset, for its xsd:schema)
    " are written "NAME:type NAME?*:type ...": the type as the reference writes it (none for a nested rowset), ? after the
    " name for a nullable column (minOccurs 0), * for an unbounded one (maxOccurs unbounded).
    TYPES:
      BEGIN OF ty_rowset,
        name         TYPE string,
        guid         TYPE string,
        description  TYPE string,
        mask         TYPE string,
        restrictions TYPE string,
        columns      TYPE string,
      END OF ty_rowset,
      ty_t_rowset TYPE STANDARD TABLE OF ty_rowset WITH EMPTY KEY.

    CLASS-METHODS get_all RETURNING VALUE(result) TYPE ty_t_rowset.
    "! The xsd:schema that opens the answer of a rowset with Content Schema or SchemaData, as the reference writes it
    "! (RowsetDefinition.writeRowsetXmlSchema): the root element of rows, the uuid type and the row type of its columns;
    "! DISCOVER_SCHEMA_ROWSETS describes its nested Restrictions (Name and Type). Empty for an unknown rowset.
    CLASS-METHODS xml_schema
      IMPORTING name          TYPE string
      RETURNING VALUE(result) TYPE string.

  PRIVATE SECTION.
ENDCLASS.

CLASS zzxxmla1_cl_xmla_rowsets IMPLEMENTATION.
  METHOD get_all.
    result = VALUE #(
      ( name = `DBSCHEMA_CATALOGS` guid = `C8B52211-5CF3-11CE-ADE5-00AA0044773D`
        description = `Identifies the physical attributes associated with catalogs accessible from the provider.`
        restrictions = `CATALOG_NAME:string`
        columns = `CATALOG_NAME:xsd:string DESCRIPTION:xsd:string ROLES:xsd:string DATE_MODIFIED?:xsd:dateTime COMPATIBILITY_LEVE` &&
          `L?:xsd:int` )
      ( name = `DBSCHEMA_COLUMNS` guid = `C8B52214-5CF3-11CE-ADE5-00AA0044773D`
        restrictions = `TABLE_CATALOG:string TABLE_SCHEMA:string TABLE_NAME:string COLUMN_NAME:string`
        columns = `TABLE_CATALOG:xsd:string TABLE_SCHEMA?:xsd:string TABLE_NAME:xsd:string COLUMN_NAME:xsd:string ORDINAL_POSITIO` &&
          `N:xsd:unsignedInt COLUMN_HAS_DEFAULT?:xsd:boolean COLUMN_FLAGS:xsd:unsignedInt IS_NULLABLE:xsd:boolean DATA_TY` &&
          `PE:xsd:unsignedShort CHARACTER_MAXIMUM_LENGTH?:xsd:unsignedInt CHARACTER_OCTET_LENGTH?:xsd:unsignedInt NUMERIC` &&
          `_PRECISION?:xsd:unsignedShort NUMERIC_SCALE?:xsd:short` )
      ( name = `DBSCHEMA_PROVIDER_TYPES` guid = `C8B5222C-5CF3-11CE-ADE5-00AA0044773D`
        restrictions = `DATA_TYPE:unsignedShort BEST_MATCH:boolean`
        columns = `TYPE_NAME:xsd:string DATA_TYPE:xsd:unsignedShort COLUMN_SIZE:xsd:unsignedInt LITERAL_PREFIX?:xsd:string LITERA` &&
          `L_SUFFIX?:xsd:string IS_NULLABLE?:xsd:boolean CASE_SENSITIVE?:xsd:boolean SEARCHABLE?:xsd:unsignedInt UNSIGNED` &&
          `_ATTRIBUTE?:xsd:boolean FIXED_PREC_SCALE?:xsd:boolean AUTO_UNIQUE_VALUE?:xsd:boolean IS_LONG?:xsd:boolean BEST` &&
          `_MATCH?:xsd:boolean` )
      ( name = `DBSCHEMA_SCHEMATA` guid = `c8b52225-5cf3-11ce-ade5-00aa0044773d`
        restrictions = `CATALOG_NAME:string SCHEMA_NAME:string SCHEMA_OWNER:string`
        columns = `CATALOG_NAME:xsd:string SCHEMA_NAME:xsd:string SCHEMA_OWNER:xsd:string` )
      ( name = `DBSCHEMA_SOURCE_TABLES` guid = `8c3f5858-2742-4976-9d65-eb4d493c693e`
        restrictions = `TABLE_CATALOG:string TABLE_SCHEMA:string TABLE_NAME:string TABLE_TYPE:string`
        columns = `TABLE_CATALOG?:xsd:string TABLE_SCHEMA?:xsd:string TABLE_NAME:xsd:string TABLE_TYPE:xsd:string` )
      ( name = `DBSCHEMA_TABLES` guid = `C8B52229-5CF3-11CE-ADE5-00AA0044773D`
        restrictions = `TABLE_CATALOG:string TABLE_SCHEMA:string TABLE_NAME:string TABLE_TYPE:string`
        columns = `TABLE_CATALOG:xsd:string TABLE_SCHEMA?:xsd:string TABLE_NAME:xsd:string TABLE_TYPE:xsd:string TABLE_GUID?:uuid` &&
          ` DESCRIPTION?:xsd:string TABLE_PROPID?:xsd:unsignedInt DATE_CREATED?:xsd:dateTime DATE_MODIFIED?:xsd:dateTime` )
      ( name = `DBSCHEMA_TABLES_INFO` guid = `c8b522e0-5cf3-11ce-ade5-00aa0044773d`
        restrictions = `TABLE_CATALOG:string TABLE_SCHEMA:string TABLE_NAME:string TABLE_TYPE:string`
        columns = `TABLE_CATALOG?:xsd:string TABLE_SCHEMA?:xsd:string TABLE_NAME:xsd:string TABLE_TYPE:xsd:string TABLE_GUID?:uui` &&
          `d BOOKMARKS:xsd:boolean BOOKMARK_TYPE?:xsd:int BOOKMARK_DATATYPE?:xsd:unsignedShort BOOKMARK_MAXIMUM_LENGTH?:x` &&
          `sd:unsignedInt BOOKMARK_INFORMATION?:xsd:unsignedInt TABLE_VERSION?:xsd:long CARDINALITY:xsd:unsignedLong DESC` &&
          `RIPTION?:xsd:string TABLE_PROPID?:xsd:unsignedInt` )
      ( name = `DISCOVER_CSDL_METADATA` guid = `87B86062-21C3-460F-B4F8-5BE98394F13B`
        description = `Returns the conceptual schema definition language (CSDL) representation of the database metadata.`
        mask = `7`
        restrictions = `CATALOG_NAME:string PERSPECTIVE_NAME:string VERSION:string`
        columns = `METADATA:xmlDocument CATALOG_NAME?:xsd:string PERSPECTIVE_NAME?:xsd:string VERSION?:xsd:string` )
      ( name = `DISCOVER_DATASOURCES` guid = `06C03D41-F66D-49F3-B1B8-987F7AF4CF18`
        description = `Returns a list of XML for Analysis data sources available on the server or Web Service.`
        restrictions = `DataSourceName:string URL:string ProviderName:string ProviderType:string AuthenticationMode:string`
        columns = `DataSourceName:xsd:string DataSourceDescription?:xsd:string URL?:xsd:string DataSourceInfo?:xsd:string Provide` &&
          `rName?:xsd:string ProviderType*:xsd:string AuthenticationMode:xsd:string` )
      ( name = `DISCOVER_ENUMERATORS` guid = `55A9E78B-ACCB-45B4-95A6-94C5065617A7`
        description = `Returns a list of names, data types, and enumeration values for enumerators supported by the provide` &&
          `r of a specific data source.`
        restrictions = `EnumName:string`
        columns = `EnumName:xsd:string EnumDescription?:xsd:string EnumType:xsd:string ElementName:xsd:string ElementDescription?` &&
          `:xsd:string ElementValue?:xsd:string` )
      ( name = `DISCOVER_KEYWORDS` guid = `1426C443-4CDD-4A40-8F45-572FAB9BBAA1`
        description = `Returns an XML list of keywords reserved by the provider.`
        restrictions = `Keyword:string`
        columns = `Keyword:xsd:string` )
      ( name = `DISCOVER_LITERALS` guid = `C3EF5ECB-0A07-4665-A140-B075722DBDC2`
        description = `Returns information about literals supported by the provider.`
        restrictions = `LiteralName:string`
        columns = `LiteralName:xsd:string LiteralValue?:xsd:string LiteralInvalidChars?:xsd:string LiteralInvalidStartingChars?:x` &&
          `sd:string LiteralMaxLength?:xsd:int LiteralNameEnumValue?:xsd:int` )
      ( name = `DISCOVER_PROPERTIES` guid = `4B40ADFB-8B09-4758-97BB-636E8AE97BCF`
        description = `Returns a list of information and values about the requested properties that are supported by the sp` &&
          `ecified data source provider.`
        restrictions = `PropertyName:string`
        columns = `PropertyName:xsd:string PropertyDescription:xsd:string PropertyType:xsd:string PropertyAccessType:xsd:string I` &&
          `sRequired:xsd:boolean Value:xsd:string` )
      ( name = `DISCOVER_SCHEMA_ROWSETS` guid = `EEA0302B-7922-4992-8991-0E605D0E5593`
        description = `Returns the names, values, and other information of all supported RequestType enumeration values.`
        restrictions = `SchemaName:string`
        columns = `SchemaName:xsd:string SchemaGuid?:uuid Restrictions?* Description:xsd:string RestrictionsMask?:xsd:unsignedLon` &&
          `g` )
      ( name = `DISCOVER_SESSIONS` guid = `0BC46A88-2B4C-4F2E-B0E2-2E1F5DE1C1D7`
        description = `Returns a list of the sessions currently open on the server.`
        restrictions = `SESSION_ID:string SESSION_SPID:int SESSION_USER_NAME:string SESSION_CURRENT_DATABASE:string`
        columns = `SESSION_ID:xsd:string SESSION_SPID:xsd:int SESSION_USER_NAME?:xsd:string SESSION_CURRENT_DATABASE?:xsd:string ` &&
          `SESSION_START_TIME?:xsd:dateTime SESSION_ELAPSED_TIME_MS?:xsd:long SESSION_IDLE_TIME_MS?:xsd:long SESSION_STAT` &&
          `US?:xsd:int` )
      ( name = `DISCOVER_XML_METADATA` guid = `3444B255-171E-4CB9-AD98-19E57888A75F`
        description = `Returns an XML document describing a requested object. The rowset that is returned always consists o` &&
          `f one row and one column.`
        restrictions = `ObjectType:string DatabaseID:string ObjectExpansion:string`
        columns = `METADATA:xsd:string ObjectType?:xsd:string DatabaseID?:xsd:string ObjectExpansion?:xsd:string` )
      ( name = `MDSCHEMA_ACTIONS` guid = `A07CCD08-8148-11D0-87BB-00C04FC33942`
        restrictions = `CATALOG_NAME:string SCHEMA_NAME:string CUBE_NAME:string ACTION_NAME:string COORDINATE:string COORDIN` &&
          `ATE_TYPE:int`
        columns = `CATALOG_NAME?:xsd:string SCHEMA_NAME?:xsd:string CUBE_NAME:xsd:string ACTION_NAME:xsd:string COORDINATE:xsd:st` &&
          `ring COORDINATE_TYPE:xsd:int` )
      ( name = `MDSCHEMA_CUBES` guid = `C8B522D8-5CF3-11CE-ADE5-00AA0044773D`
        restrictions = `CATALOG_NAME:string SCHEMA_NAME:string CUBE_NAME:string CUBE_TYPE:string BASE_CUBE_NAME:string CUBE_` &&
          `SOURCE:int`
        columns = `CATALOG_NAME?:xsd:string SCHEMA_NAME?:xsd:string CUBE_NAME:xsd:string CUBE_TYPE:xsd:string CUBE_GUID?:uuid CRE` &&
          `ATED_ON?:xsd:dateTime LAST_SCHEMA_UPDATE?:xsd:dateTime SCHEMA_UPDATED_BY?:xsd:string LAST_DATA_UPDATE?:xsd:dat` &&
          `eTime DATA_UPDATED_BY?:xsd:string DESCRIPTION?:xsd:string IS_DRILLTHROUGH_ENABLED:xsd:boolean IS_LINKABLE:xsd:` &&
          `boolean IS_WRITE_ENABLED:xsd:boolean IS_SQL_ENABLED:xsd:boolean CUBE_CAPTION?:xsd:string BASE_CUBE_NAME?:xsd:s` &&
          `tring DIMENSIONS? SETS? MEASURES? CUBE_SOURCE?:xsd:int` )
      ( name = `MDSCHEMA_DIMENSIONS` guid = `C8B522D9-5CF3-11CE-ADE5-00AA0044773D`
        restrictions = `CATALOG_NAME:string SCHEMA_NAME:string CUBE_NAME:string DIMENSION_NAME:string DIMENSION_UNIQUE_NAME:` &&
          `string`
        columns = `CATALOG_NAME?:xsd:string SCHEMA_NAME?:xsd:string CUBE_NAME:xsd:string DIMENSION_NAME:xsd:string DIMENSION_UNIQ` &&
          `UE_NAME:xsd:string DIMENSION_GUID?:uuid DIMENSION_CAPTION:xsd:string DIMENSION_ORDINAL:xsd:unsignedInt DIMENSI` &&
          `ON_TYPE:xsd:short DIMENSION_CARDINALITY:xsd:unsignedInt DEFAULT_HIERARCHY:xsd:string DESCRIPTION?:xsd:string I` &&
          `S_VIRTUAL?:xsd:boolean IS_READWRITE?:xsd:boolean DIMENSION_UNIQUE_SETTINGS?:xsd:int DIMENSION_MASTER_UNIQUE_NA` &&
          `ME?:xsd:string DIMENSION_IS_VISIBLE?:xsd:boolean HIERARCHIES?` )
      ( name = `MDSCHEMA_FUNCTIONS` guid = `A07CCD07-8148-11D0-87BB-00C04FC33942`
        restrictions = `FUNCTION_NAME:string ORIGIN:int INTERFACE_NAME:string LIBRARY_NAME:string`
        columns = `FUNCTION_NAME:xsd:string DESCRIPTION?:xsd:string PARAMETER_LIST?:xsd:string RETURN_TYPE:xsd:int ORIGIN:xsd:int` &&
          ` INTERFACE_NAME:xsd:string LIBRARY_NAME?:xsd:string CAPTION?:xsd:string` )
      ( name = `MDSCHEMA_HIERARCHIES` guid = `C8B522DA-5CF3-11CE-ADE5-00AA0044773D`
        restrictions = `CATALOG_NAME:string SCHEMA_NAME:string CUBE_NAME:string DIMENSION_UNIQUE_NAME:string HIERARCHY_NAME:` &&
          `string HIERARCHY_UNIQUE_NAME:string HIERARCHY_ORIGIN:unsignedShort CUBE_SOURCE:unsignedShort HIERARC` &&
          `HY_VISIBILITY:unsignedShort`
        columns = `CATALOG_NAME?:xsd:string SCHEMA_NAME?:xsd:string CUBE_NAME:xsd:string DIMENSION_UNIQUE_NAME:xsd:string HIERARC` &&
          `HY_NAME:xsd:string HIERARCHY_UNIQUE_NAME:xsd:string HIERARCHY_GUID?:uuid HIERARCHY_CAPTION:xsd:string DIMENSIO` &&
          `N_TYPE:xsd:short HIERARCHY_CARDINALITY:xsd:unsignedInt DEFAULT_MEMBER?:xsd:string ALL_MEMBER?:xsd:string DESCR` &&
          `IPTION?:xsd:string STRUCTURE:xsd:short IS_VIRTUAL:xsd:boolean IS_READWRITE:xsd:boolean DIMENSION_UNIQUE_SETTIN` &&
          `GS:xsd:int DIMENSION_IS_VISIBLE:xsd:boolean HIERARCHY_ORDINAL:xsd:unsignedInt DIMENSION_IS_SHARED:xsd:boolean ` &&
          `HIERARCHY_IS_VISIBLE:xsd:boolean HIERARCHY_ORIGIN?:xsd:unsignedShort HIERARCHY_DISPLAY_FOLDER?:xsd:string CUBE` &&
          `_SOURCE?:xsd:unsignedShort HIERARCHY_VISIBILITY?:xsd:unsignedShort PARENT_CHILD?:xsd:boolean LEVELS?` )
      ( name = `MDSCHEMA_KPIS` guid = `2AE44109-ED3D-4842-B16F-B694D1CB0E3F`
        restrictions = `CATALOG_NAME:string SCHEMA_NAME:string CUBE_NAME:string KPI_NAME:string`
        columns = `CATALOG_NAME?:xsd:string SCHEMA_NAME?:xsd:string CUBE_NAME?:xsd:string MEASUREGROUP_NAME:xsd:string KPI_NAME?:` &&
          `xsd:string KPI_CAPTION:xsd:string KPI_DESCRIPTION:xsd:string KPI_DISPLAY_FOLDER:xsd:string KPI_VALUE:xsd:strin` &&
          `g KPI_GOAL:xsd:string KPI_STATUS:xsd:string KPI_TREND:xsd:string KPI_STATUS_GRAPHIC:xsd:string KPI_TREND_GRAPH` &&
          `IC:xsd:string KPI_WEIGHT:xsd:string KPI_CURRENT_TIME_MEMBER:xsd:string KPI_PARENT_KPI_NAME:xsd:string SCOPE:xs` &&
          `d:int` )
      ( name = `MDSCHEMA_LEVELS` guid = `C8B522DB-5CF3-11CE-ADE5-00AA0044773D`
        restrictions = `CATALOG_NAME:string SCHEMA_NAME:string CUBE_NAME:string DIMENSION_UNIQUE_NAME:string HIERARCHY_UNIQU` &&
          `E_NAME:string LEVEL_NAME:string LEVEL_UNIQUE_NAME:string LEVEL_ORIGIN:unsignedShort CUBE_SOURCE:unsi` &&
          `gnedShort LEVEL_VISIBILITY:unsignedShort`
        columns = `CATALOG_NAME?:xsd:string SCHEMA_NAME?:xsd:string CUBE_NAME:xsd:string DIMENSION_UNIQUE_NAME:xsd:string HIERARC` &&
          `HY_UNIQUE_NAME:xsd:string LEVEL_NAME:xsd:string LEVEL_UNIQUE_NAME:xsd:string LEVEL_GUID?:uuid LEVEL_CAPTION:xs` &&
          `d:string LEVEL_NUMBER:xsd:unsignedInt LEVEL_CARDINALITY:xsd:unsignedInt LEVEL_TYPE:xsd:int CUSTOM_ROLLUP_SETTI` &&
          `NGS:xsd:int LEVEL_UNIQUE_SETTINGS:xsd:int LEVEL_IS_VISIBLE:xsd:boolean DESCRIPTION?:xsd:string LEVEL_ORIGIN?:x` &&
          `sd:unsignedShort CUBE_SOURCE?:xsd:unsignedShort LEVEL_VISIBILITY?:xsd:unsignedShort` )
      ( name = `MDSCHEMA_MEASUREGROUP_DIMENSIONS` guid = `a07ccd33-8148-11d0-87bb-00c04fc33942`
        restrictions = `CATALOG_NAME:string SCHEMA_NAME:string CUBE_NAME:string MEASUREGROUP_NAME:string DIMENSION_UNIQUE_NA` &&
          `ME:string`
        columns = `CATALOG_NAME?:xsd:string SCHEMA_NAME?:xsd:string CUBE_NAME:xsd:string MEASUREGROUP_NAME?:xsd:string MEASUREGRO` &&
          `UP_CARDINALITY?:xsd:string DIMENSION_UNIQUE_NAME?:xsd:string DIMENSION_CARDINALITY?:xsd:string DIMENSION_IS_VI` &&
          `SIBLE?:xsd:boolean DIMENSION_IS_FACT_DIMENSION?:xsd:boolean DIMENSION_PATH?:xsd:string DIMENSION_GRANULARITY?:` &&
          `xsd:string` )
      ( name = `MDSCHEMA_MEASUREGROUPS` guid = `E1625EBF-FA96-42FD-BEA6-DB90ADAFD96B`
        restrictions = `CATALOG_NAME:string SCHEMA_NAME:string CUBE_NAME:string MEASUREGROUP_NAME:string`
        columns = `CATALOG_NAME?:xsd:string SCHEMA_NAME?:xsd:string CUBE_NAME?:xsd:string MEASUREGROUP_NAME?:xsd:string DESCRIPTI` &&
          `ON?:xsd:string IS_WRITE_ENABLED?:xsd:boolean MEASUREGROUP_CAPTION?:xsd:string` )
      ( name = `MDSCHEMA_MEASURES` guid = `C8B522DC-5CF3-11CE-ADE5-00AA0044773D`
        restrictions = `CATALOG_NAME:string SCHEMA_NAME:string CUBE_NAME:string MEASURE_NAME:string MEASURE_UNIQUE_NAME:stri` &&
          `ng MEASUREGROUP_NAME:string CUBE_SOURCE:unsignedShort MEASURE_VISIBILITY:unsignedShort`
        columns = `CATALOG_NAME?:xsd:string SCHEMA_NAME?:xsd:string CUBE_NAME:xsd:string MEASURE_NAME:xsd:string MEASURE_UNIQUE_N` &&
          `AME:xsd:string MEASURE_CAPTION:xsd:string MEASURE_GUID?:uuid MEASURE_AGGREGATOR:xsd:int DATA_TYPE:xsd:unsigned` &&
          `Short MEASURE_IS_VISIBLE:xsd:boolean LEVELS_LIST?:xsd:string DESCRIPTION?:xsd:string MEASUREGROUP_NAME?:xsd:st` &&
          `ring MEASURE_DISPLAY_FOLDER?:xsd:string DEFAULT_FORMAT_STRING?:xsd:string CUBE_SOURCE?:xsd:unsignedShort MEASU` &&
          `RE_VISIBILITY?:xsd:unsignedShort` )
      ( name = `MDSCHEMA_MEMBERS` guid = `C8B522DE-5CF3-11CE-ADE5-00AA0044773D`
        restrictions = `CATALOG_NAME:string SCHEMA_NAME:string CUBE_NAME:string DIMENSION_UNIQUE_NAME:string HIERARCHY_UNIQU` &&
          `E_NAME:string LEVEL_UNIQUE_NAME:string LEVEL_NUMBER:unsignedInt MEMBER_NAME:string MEMBER_UNIQUE_NAM` &&
          `E:string MEMBER_TYPE:int MEMBER_CAPTION:string TREE_OP:int`
        columns = `CATALOG_NAME?:xsd:string SCHEMA_NAME?:xsd:string CUBE_NAME:xsd:string DIMENSION_UNIQUE_NAME:xsd:string HIERARC` &&
          `HY_UNIQUE_NAME:xsd:string LEVEL_UNIQUE_NAME:xsd:string LEVEL_NUMBER:xsd:unsignedInt MEMBER_ORDINAL:xsd:unsigne` &&
          `dInt MEMBER_NAME:xsd:string MEMBER_UNIQUE_NAME:xsd:string MEMBER_TYPE:xsd:int MEMBER_GUID?:uuid MEMBER_CAPTION` &&
          `:xsd:string CHILDREN_CARDINALITY:xsd:unsignedInt PARENT_LEVEL:xsd:unsignedInt PARENT_UNIQUE_NAME?:xsd:string P` &&
          `ARENT_COUNT:xsd:unsignedInt TREE_OP?:xsd:string DEPTH?:xsd:int` )
      ( name = `MDSCHEMA_PROPERTIES` guid = `C8B522DD-5CF3-11CE-ADE5-00AA0044773D`
        restrictions = `CATALOG_NAME:string SCHEMA_NAME:string CUBE_NAME:string DIMENSION_UNIQUE_NAME:string HIERARCHY_UNIQU` &&
          `E_NAME:string LEVEL_UNIQUE_NAME:string MEMBER_UNIQUE_NAME:string PROPERTY_NAME:string PROPERTY_TYPE:` &&
          `short PROPERTY_CONTENT_TYPE:short PROPERTY_ORIGIN:unsignedShort CUBE_SOURCE:unsignedShort PROPERTY_V` &&
          `ISIBILITY:unsignedShort`
        columns = `CATALOG_NAME?:xsd:string SCHEMA_NAME?:xsd:string CUBE_NAME?:xsd:string DIMENSION_UNIQUE_NAME?:xsd:string HIERA` &&
          `RCHY_UNIQUE_NAME?:xsd:string LEVEL_UNIQUE_NAME?:xsd:string MEMBER_UNIQUE_NAME?:xsd:string PROPERTY_TYPE:xsd:sh` &&
          `ort PROPERTY_NAME:xsd:string PROPERTY_CAPTION:xsd:string DATA_TYPE:xsd:unsignedShort PROPERTY_CONTENT_TYPE?:xs` &&
          `d:short DESCRIPTION?:xsd:string PROPERTY_ORIGIN?:xsd:unsignedShort CUBE_SOURCE?:xsd:unsignedShort PROPERTY_VIS` &&
          `IBILITY?:xsd:unsignedShort` )
      ( name = `MDSCHEMA_SETS` guid = `A07CCD0B-8148-11D0-87BB-00C04FC33942`
        restrictions = `CATALOG_NAME:string SCHEMA_NAME:string CUBE_NAME:string SET_NAME:string SCOPE:int SET_CAPTION:string`
        columns = `CATALOG_NAME?:xsd:string SCHEMA_NAME?:xsd:string CUBE_NAME:xsd:string SET_NAME:xsd:string SCOPE:xsd:int DESCRI` &&
          `PTION?:xsd:string EXPRESSION?:xsd:string DIMENSIONS?:xsd:string SET_CAPTION?:xsd:string SET_DISPLAY_FOLDER?:xs` &&
          `d:string` ) ).
  ENDMETHOD.

  METHOD xml_schema.
    DATA(nl) = cl_abap_char_utilities=>newline.
    DATA(rowsets) = get_all( ).
    READ TABLE rowsets INTO DATA(rowset) WITH KEY name = name.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    DATA(elements) = VALUE string( ).
    SPLIT rowset-columns AT ` ` INTO TABLE DATA(columns).
    LOOP AT columns INTO DATA(column).
      " the type is the rest after the first colon (xsd:string has one of its own)
      SPLIT column AT `:` INTO DATA(column_name) DATA(type).
      DATA(nullable) = xsdbool( column_name CS `?` ).
      DATA(unbounded) = xsdbool( column_name CS `*` ).
      column_name = replace( val = replace( val = column_name sub = `?` with = `` occ = 0 ) sub = `*` with = `` occ = 0 ).
      DATA(attributes) = |sql:field="{ column_name }" name="{ column_name }"| &&
        COND string( WHEN type IS NOT INITIAL THEN | type="{ type }"| ) &&
        COND string( WHEN nullable = abap_true THEN ` minOccurs="0"` ) &&
        COND string( WHEN unbounded = abap_true THEN ` maxOccurs="unbounded"` ).
      IF rowset-name = `DISCOVER_SCHEMA_ROWSETS` AND column_name = `Restrictions`.
        elements = elements &&
          `            <xsd:element ` && attributes && `>` && nl &&
          `              <xsd:complexType>` && nl &&
          `                <xsd:sequence>` && nl &&
          `                  <xsd:element name="Name" type="xsd:string" sql:field="Name"/>` && nl &&
          `                  <xsd:element name="Type" type="xsd:string" sql:field="Type"/>` && nl &&
          `                </xsd:sequence>` && nl &&
          `              </xsd:complexType>` && nl &&
          `            </xsd:element>` && nl.
      ELSE.
        elements = elements && `            <xsd:element ` && attributes && `/>` && nl.
      ENDIF.
    ENDLOOP.
    result =
      `      <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns="urn:schemas-microsoft-com:xml-analysis:rowset"` &&
      ` xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:sql="urn:schemas-microsoft-com:xml-sql"` &&
      ` targetNamespace="urn:schemas-microsoft-com:xml-analysis:rowset" elementFormDefault="qualified">` && nl &&
      `        <xsd:element name="root">` && nl &&
      `          <xsd:complexType>` && nl &&
      `            <xsd:sequence>` && nl &&
      `              <xsd:element name="row" type="row" minOccurs="0" maxOccurs="unbounded"/>` && nl &&
      `            </xsd:sequence>` && nl &&
      `          </xsd:complexType>` && nl &&
      `        </xsd:element>` && nl &&
      `        <xsd:simpleType name="uuid">` && nl &&
      `          <xsd:restriction base="xsd:string">` && nl &&
      `            <xsd:pattern value="[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"/>` && nl &&
      `          </xsd:restriction>` && nl &&
      `        </xsd:simpleType>` && nl &&
      `        <xsd:complexType name="row">` && nl &&
      `          <xsd:sequence>` && nl &&
      elements &&
      `          </xsd:sequence>` && nl &&
      `        </xsd:complexType>` && nl &&
      `      </xsd:schema>` && nl.
  ENDMETHOD.
ENDCLASS.
