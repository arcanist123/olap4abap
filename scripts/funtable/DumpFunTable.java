import mondrian.olap.fun.BuiltinFunTable;
import mondrian.olap.fun.GlobalFunTable;
import mondrian.olap.fun.UdfResolver;
import mondrian.olap.fun.FunInfo;
import mondrian.olap.fun.Resolver;

import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;

/**
 * Prints Mondrian's built-in function table, one resolver per line, in the order of FunTableImpl.getResolvers(), then
 * the user-defined functions of GlobalFunTable (META-INF/services, e.g. IN and MATCHES), which every schema has:
 * resolver class, name, syntax, the signatures as returnCategory:parameterCategories (comma separated, signatures
 * separated by ;), the reserved words, and the signature text. Run in the eMondrian container by
 * scripts/generate-funtable.py.
 */
public class DumpFunTable {
    public static void main(String[] args) throws Exception {
        Method make = FunInfo.class.getDeclaredMethod("make", Resolver.class);
        make.setAccessible(true);
        List<Resolver> all = new ArrayList<>(BuiltinFunTable.instance().getResolvers());
        for (Resolver resolver : GlobalFunTable.instance().getResolvers()) {
            if (resolver instanceof UdfResolver) {
                all.add(resolver);
            }
        }
        for (Resolver resolver : all) {
            FunInfo info = (FunInfo) make.invoke(null, resolver);
            StringBuilder signatures = new StringBuilder();
            int[] returns = info.getReturnCategories();
            int[][] parameters = info.getParameterCategories();
            if (returns != null) {
                for (int i = 0; i < returns.length; i++) {
                    if (i > 0) {
                        signatures.append(';');
                    }
                    signatures.append(returns[i]).append(':');
                    for (int j = 0; j < parameters[i].length; j++) {
                        if (j > 0) {
                            signatures.append(',');
                        }
                        signatures.append(parameters[i][j]);
                    }
                }
            }
            System.out.println(
                resolver.getClass().getName().replace("mondrian.olap.fun.", "") + "\t"
                + resolver.getName() + "\t"
                + resolver.getSyntax() + "\t"
                + signatures + "\t"
                + String.join(",", resolver.getReservedWords()) + "\t"
                + resolver.getSignature());
        }
    }
}
