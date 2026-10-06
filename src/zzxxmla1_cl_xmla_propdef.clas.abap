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
CLASS zzxxmla1_cl_xmla_propdef DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    " The XMLA properties this server knows, in the reference's order (xmla.PropertyDefinition). The default
    " value of Catalog is not fixed: DISCOVER_PROPERTIES derives it from the available catalogs.
    TYPES:
      BEGIN OF ty_property,
        name          TYPE string,
        data_type     TYPE string,
        access        TYPE string,
        default_value TYPE string,
        description   TYPE string,
      END OF ty_property,
      ty_t_property TYPE STANDARD TABLE OF ty_property WITH EMPTY KEY.

    CLASS-METHODS get_all RETURNING VALUE(result) TYPE ty_t_property.

  PRIVATE SECTION.
ENDCLASS.

CLASS zzxxmla1_cl_xmla_propdef IMPLEMENTATION.
  METHOD get_all.
    result = VALUE #(
      ( name = `AxisFormat` data_type = `Enumeration` access = `Write` default_value = ``
        description = `Determines the format used within an MDDataSet result set to describe the axes of the multidimensional dataset` &&
          `. This property can have the values listed in the following table: TupleFormat (default), ClusterFormat, Custo` &&
          `mFormat.` )
      ( name = `BeginRange` data_type = `Integer` access = `Write` default_value = `-1`
        description = `Contains a zero-based integer value corresponding to a CellOrdinal attribute value. (The CellOrdinal attribute` &&
          ` is part of the Cell element in the CellData section of MDDataSet.)` &&
          cl_abap_char_utilities=>newline &&
          `Used together with the EndRange property, the client application can use this property to restrict an OLAP dat` &&
          `aset returned by a command to a specific range of cells. If -1 is specified, all cells up to the cell specifie` &&
          `d in the EndRange property are returned.` &&
          cl_abap_char_utilities=>newline &&
          `The default value for this property is -1.` )
      ( name = `Catalog` data_type = `string` access = `ReadWrite` default_value = ``
        description = `When establishing a session with an Analysis Services instance to send an XMLA command, this property is equiv` &&
          `alent to the OLE DB property, DBPROP_INIT_CATALOG.` &&
          cl_abap_char_utilities=>newline &&
          `When you set this property during a session to change the current database for the session, this property is e` &&
          `quivalent to the OLE DB property, DBPROP_CURRENTCATALOG.` &&
          cl_abap_char_utilities=>newline &&
          `The default value for this property is an empty string.` )
      ( name = `Content` data_type = `EnumString` access = `Write` default_value = `SchemaData`
        description = `An enumerator that specifies what type of data is returned in the result set.` &&
          cl_abap_char_utilities=>newline &&
          `None: Allows the structure of the command to be verified, but not executed. Analogous to using Prepare to chec` &&
          `k syntax, and so on.` &&
          cl_abap_char_utilities=>newline &&
          `Schema: Contains the XML schema (which indicates column information, and so on) that relates to the requested ` &&
          `query.` &&
          cl_abap_char_utilities=>newline &&
          `Data: Contains only the data that was requested.` &&
          cl_abap_char_utilities=>newline &&
          `SchemaData: Returns both the schema information as well as the data.` )
      ( name = `Cube` data_type = `string` access = `ReadWrite` default_value = ``
        description = `The cube context for the Command parameter. If the command contains a cube name (such as an MDX FROM clause) t` &&
          `he setting of this property is ignored.` )
      ( name = `DataSourceInfo` data_type = `string` access = `ReadWrite` default_value = ``
        description = `A string containing provider specific information, required to access the data source.` )
      ( name = `Deep` data_type = `Boolean` access = `ReadWrite` default_value = ``
        description = `In an MDSCHEMA_CUBES request, whether to include sub-elements (dimensions, hierarchies, levels, measures, name` &&
          `d sets) of each cube.` )
      ( name = `EmitInvisibleMembers` data_type = `Boolean` access = `ReadWrite` default_value = ``
        description = `Whether to include members whose VISIBLE property is false, or measures whose MEASURE_IS_VISIBLE property is f` &&
          `alse.` )
      ( name = `EndRange` data_type = `Integer` access = `Write` default_value = `-1`
        description = `An integer value corresponding to a CellOrdinal used to restrict an MDDataSet returned by a command to a speci` &&
          `fic range of cells. Used in conjunction with the BeginRange property. If unspecified, all cells are returned i` &&
          `n the rowset. The value -1 means unspecified.` )
      ( name = `Format` data_type = `EnumString` access = `Write` default_value = `Native`
        description = `Enumerator that determines the format of the returned result set. Values include:` &&
          cl_abap_char_utilities=>newline &&
          `Tabular: a flat or hierarchical rowset. Similar to the XML RAW format in SQL. The Format property should be se` &&
          `t to Tabular for OLE DB for Data Mining commands.` &&
          cl_abap_char_utilities=>newline &&
          `Multidimensional: Indicates that the result set will use the MDDataSet format (Execute method only).` &&
          cl_abap_char_utilities=>newline &&
          `Native: The client does not request a specific format, so the provider may return the format  appropriate to t` &&
          `he query. (The actual result type is identified by namespace of the result.)` )
      ( name = `LocaleIdentifier` data_type = `UnsignedInteger` access = `ReadWrite` default_value = `None`
        description = `Use this to read or set the numeric locale identifier for this request. The default is provider-specific.` &&
          cl_abap_char_utilities=>newline &&
          `For the complete hexadecimal list of language identifiers, search on "Language Identifiers" in the MSDN Librar` &&
          `y at http://www.msdn.microsoft.com.` &&
          cl_abap_char_utilities=>newline &&
          `As an extension to the XMLA standard, olap4abap also allows locale codes as specified by ISO-639 and ISO-3166 a` &&
          `nd as used by Java; for example 'en-US'.` &&
          cl_abap_char_utilities=>newline )
      ( name = `MDXSupport` data_type = `EnumString` access = `Read` default_value = `Core`
        description = `Enumeration that describes the degree of MDX support. At initial release Core is the only value in the enumera` &&
          `tion. In future releases, other values will be defined for this enumeration.` )
      ( name = `Password` data_type = `string` access = `Read` default_value = ``
        description = `This property is deprecated in XMLA 1.1. To support legacy applications, the provider accepts but ignores the ` &&
          `Password property setting when it is used with the Discover and Execute method` )
      ( name = `ProviderName` data_type = `string` access = `Read` default_value = `olap4abap XML for Analysis Provider`
        description = `The XML for Analysis Provider name.` )
      ( name = `ProviderVersion` data_type = `string` access = `Read` default_value = `13.0.5026.0`
        description = `The version of the olap4abap XMLA Provider` )
      ( name = `ResponseMimeType` data_type = `string` access = `ReadWrite` default_value = `None`
        description = `Accepted mime type for RPC response; accepted are 'text/xml' (default), 'application/xml' (equivalent to 'text` &&
          `/xml'), or 'application/json'. If not specified, value in the 'Accept' header of the HTTP request is used.` )
      ( name = `StateSupport` data_type = `EnumString` access = `Read` default_value = `None`
        description = `Property that specifies the degree of support in the provider for state. For information about state in XML fo` &&
          `r Analysis, see "Support for Statefulness in XML for Analysis." Minimum enumeration values are as follows:` &&
          cl_abap_char_utilities=>newline &&
          `None - No support for sessions or stateful operations.` &&
          cl_abap_char_utilities=>newline &&
          `Sessions - Provider supports sessions.` )
      ( name = `Timeout` data_type = `UnsignedInteger` access = `ReadWrite` default_value = `Undefined`
        description = `A numeric time-out specifying in seconds the amount of time to wait for a request to be successful.` )
      ( name = `UserName` data_type = `string` access = `Read` default_value = ``
        description = `Returns the UserName the server associates with the command.` &&
          cl_abap_char_utilities=>newline &&
          `This property is deprecated as writeable in XMLA 1.1. To support legacy applications, servers accept but ignor` &&
          `e the password setting when it is used with the Execute method.` )
      ( name = `VisualMode` data_type = `Enumeration` access = `Write` default_value = `1`
        description = `This property is equivalent to the OLE DB property, MDPROP_VISUALMODE.` &&
          cl_abap_char_utilities=>newline &&
          `The default value for this property is zero (0), equivalent to DBPROPVAL_VISUAL_MODE_DEFAULT.` )
      ( name = `TableFields` data_type = `string` access = `Read` default_value = ``
        description = `List of fields to return for drill-through.` &&
          cl_abap_char_utilities=>newline &&
          `The default value of this property is the empty string,in which case, all fields are returned.` )
      ( name = `AdvancedFlag` data_type = `Boolean` access = `Read` default_value = `false`
        description = `` )
      ( name = `SafetyOptions` data_type = `Integer` access = `ReadWrite` default_value = `0`
        description = `Determines whether unsafe libraries can be registered and loaded by client applications.` )
      ( name = `MdxMissingMemberMode` data_type = `string` access = `Write` default_value = ``
        description = `Indicates whether missing members are ignored in MDX statements.` )
      ( name = `DbpropMsmdMDXCompatibility` data_type = `Integer` access = `ReadWrite` default_value = `0`
        description = `An enumeration value that determines how placeholder members in a ragged or` &&
          cl_abap_char_utilities=>newline &&
          `unbalanced hierarchy are treated.` )
      ( name = `MdpropMdxSubqueries` data_type = `Integer` access = `Read` default_value = `63`
        description = `A bitmask that indicates the level of support for subqueries in MDX.` )
      ( name = `MdpropMdxDrillFunctions` data_type = `Integer` access = `Read` default_value = `7`
        description = `A bitmask indicating support for drilldown and drillup groups of functions.` )
      ( name = `ClientProcessID` data_type = `Integer` access = `ReadWrite` default_value = `0`
        description = `The ID of the client process.` )
      ( name = `SspropInitAppName` data_type = `string` access = `ReadWrite` default_value = ``
        description = `The name of the client application.` )
      ( name = `DbpropMsmdSubqueries` data_type = `Integer` access = `ReadWrite` default_value = `1`
        description = `An enumeration value that determines the behavior of subqueries.` ) ).
  ENDMETHOD.
ENDCLASS.