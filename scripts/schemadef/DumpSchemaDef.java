import java.nio.file.Files;
import java.nio.file.Path;

import mondrian.olap.MondrianDef;
import org.eigenbase.xom.DOMWrapper;
import org.eigenbase.xom.Parser;
import org.eigenbase.xom.XOMUtil;

/**
 * Parses Mondrian schema files as RolapSchema.load does (XOMUtil's default parser, then new MondrianDef.Schema) and
 * prints, per file, a line "=== <file>" followed by the schema written back with toXML(), or by "ERROR: <message>"
 * if parsing fails. Run in the eMondrian container against the jars of the web app (see
 * scripts/generate-schema-def.py); the output is the reference for ZZXXMLA1_CL_SCHEMA_DEF.
 */
public class DumpSchemaDef {
    public static void main(String[] args) throws Exception {
        for (String file : args) {
            System.out.println("=== " + file);
            String xml = Files.readString(Path.of(file));
            try {
                Parser parser = XOMUtil.createDefaultParser();
                DOMWrapper def = parser.parse(xml);
                MondrianDef.Schema schema = new MondrianDef.Schema(def);
                System.out.print(schema.toXML());
            } catch (Exception e) {
                System.out.println("ERROR: " + e.getMessage());
            }
        }
    }
}
