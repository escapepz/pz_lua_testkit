import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Stream;

import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;
import se.krka.kahlua.vm.LuaClosure;
import se.krka.kahlua.vm.Platform;

/**
 * Gate2 runner: executes pzspec suites on the REAL Project Zomboid Kahlua VM.
 *
 * Clean-room: this file contains no game source. Game classes are only
 * referenced by name via reflection, resolved at runtime from the user's
 * local projectzomboid.jar (never shipped by this project).
 *
 * JVM working directory MUST be the PZ game dir: the game's J2SEPlatform
 * loads "stdlib.lua" relative to CWD.
 *
 * Usage:
 *   java -cp projectzomboid.jar;<this-classes> PzKahluaRunner <kitRoot> <spec...>
 *   spec args may be files or directories (dirs scanned for *_spec.lua).
 *
 * Phase 6 GlobalObject exposure: the engine-injected globals (getType-style
 * helpers, instanceof, require, getSquare family, ...) are exposed into the
 * env by reflecting zombie.Lua.LuaManager$GlobalObject's @LuaMethod static
 * methods through the game's own Kahlua exposer (bounded to that one class).
 *
 * Mod mode (Phase 6 parity subset, mirrors gate1 runner.prepare_mod):
 *   --mod <dir> | --mod=<dir>      mod under test — B41 single root
 *                                  (<dir>/mod.info) or B42 dual layout
 *                                  (<dir>/common/ + numeric <versionDir>/,
 *                                  common before version); the mod's media/lua
 *                                  auto-executes in engine load order after
 *                                  env setup, before specs load
 *   --modpath <dir>[;<dir>...]     ordered dep search dirs — mod.info require=
 *                                  tokens resolve as <searchDir>/<token>/ and
 *                                  contribute require ROOTS ONLY (no auto-exec)
 *   --ctx <sp|client|server>       load context (default "sp"): server
 *                                  executes shared+server only; sp/client
 *                                  executes shared+client+server; client/ is
 *                                  a require root in every ctx
 * With --mod and no explicit spec args, specs default to the mod's TESTS
 * dirs. The loader's output is recorded in the __PZ_MOD_INFO global
 * (base/ctx/roots/load_files/deps/spec_dirs) for parity specs.
 */
public class PzKahluaRunner {

    private static final String[] SUBS = { "shared", "client", "server" };

    private static final class ModInfo {
        final Path base;
        final String ctx;
        final List<String> roots = new ArrayList<>();
        final List<String> loadFiles = new ArrayList<>();
        final List<String> deps = new ArrayList<>();
        final List<String> specDirs = new ArrayList<>();

        ModInfo(Path base, String ctx) {
            this.base = base;
            this.ctx = ctx;
        }
    }

    private static final class Layout {
        final List<Path> dirs = new ArrayList<>();
        Path info;

        boolean found() {
            return info != null;
        }
    }

    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            System.err.println("usage: PzKahluaRunner <kitRoot> <spec-file-or-dir> [...]"
                    + " [--mod <dir>] [--modpath <dir>[;<dir>...]] [--ctx <sp|client|server>]");
            System.exit(2);
        }
        Path kitRoot = Path.of(args[0]).toAbsolutePath().normalize();
        List<Path> specArgs = new ArrayList<>();
        String modDir = null;
        List<String> modPathArg = new ArrayList<>();
        String ctx = "sp";
        int explicitSpecArgs = 0;
        for (int i = 1; i < args.length; i++) {
            String a = args[i];

            if (a.equals("--mod") && i + 1 < args.length
                    && !args[i + 1].startsWith("--")) {
                modDir = args[++i];
            } else if (a.startsWith("--mod=")) {
                modDir = a.substring(6);
            } else if (a.equals("--modpath") && i + 1 < args.length
                    && !args[i + 1].startsWith("--")) {
                addModPathDirs(modPathArg, args[++i]);
            } else if (a.startsWith("--modpath=")) {
                addModPathDirs(modPathArg, a.substring(10));
            } else if (a.equals("--ctx") && i + 1 < args.length
                    && !args[i + 1].startsWith("--")) {
                ctx = args[++i];
            } else if (a.startsWith("--ctx=")) {
                ctx = a.substring(6);
            } else if (a.startsWith("--")) {

                System.err.println("unknown or value-missing option: " + a);
                System.exit(2);
            } else {
                explicitSpecArgs++;
                int before = specArgs.size();
                collect(Path.of(a).toAbsolutePath(), specArgs);
                if (specArgs.size() == before) {
                    System.err.println("spec arg '" + a
                            + "': collected no *_spec.lua files");
                }
            }
        }

        if (explicitSpecArgs > 0 && specArgs.isEmpty()) {
            System.err.println(
                    "explicit spec args collected no *_spec.lua files");
            System.exit(2);
        }

        J2SEPlatform platform = new J2SEPlatform();
        KahluaTable env = platform.newEnvironment();
        KahluaConverterManager cm = new KahluaConverterManager();
        installGameConverters(cm);
        installGameEvents(platform, env, cm);
        KahluaThread thread = new KahluaThread(System.out, platform, env);
        thread.debugOwnerThread = Thread.currentThread();
        installGlobalObject(cm, platform, env, thread);

        env.rawset("PZ_GATE", "gate2");

        ModInfo mod = null;
        if (modDir != null && !modDir.isEmpty()) {
            mod = loadMod(Path.of(unquote(modDir)).toAbsolutePath().normalize(),
                    ctx, modPathArg, thread, env);
        }

        Object[] inspectResult =
                loadLua(thread, kitRoot.resolve("src/vendor/inspect.lua"), env);
        if (inspectResult != null && inspectResult.length > 1
                && inspectResult[1] instanceof KahluaTable) {
            // PZ Kahlua's pcall cannot dispatch a __call table ("tried to call

            // instead of the module table; fmt only needs a callable.
            Object fn = ((KahluaTable) inspectResult[1]).rawget("inspect");
            env.rawset("__inspect", fn != null ? fn : inspectResult[1]);
        }

        Object[] eventsListResult =
                loadLua(thread, kitRoot.resolve("src/gate1/stubs/events_list.lua"), env);
        if (eventsListResult != null && eventsListResult.length > 1
                && eventsListResult[1] instanceof KahluaTable) {
            env.rawset("__pz_events_list", eventsListResult[1]);
        }

        loadLua(thread, kitRoot.resolve("src/pzspec.lua"), env);

        List<Path> specs = new ArrayList<>(specArgs);
        if (specs.isEmpty() && mod != null) {
            for (String d : mod.specDirs) {
                collect(Path.of(d).toAbsolutePath(), specs);
            }
        }
        if (specs.isEmpty()) {
            System.err.println("no *_spec.lua files found");
            System.exit(2);
        }
        int loadFailures = 0;
        for (Path spec : specs) {
            try {
                loadLua(thread, spec, env);
            } catch (Throwable t) {
                loadFailures++;
                System.out.println("SPEC LOAD FAIL " + spec + ": " + t);
            }
        }
        if (loadFailures > 0) {
            System.out.println("total=0 passed=0 failed=" + loadFailures);
            System.exit(1);
        }

        Object pzspec = env.rawget("__pzspec");
        if (!(pzspec instanceof KahluaTable)) {
            System.err.println("__pzspec missing — src/pzspec.lua not loaded?");
            System.exit(2);
        }
        Object runFn = ((KahluaTable) pzspec).rawget("run");
        Object[] result = thread.pcall(runFn, new Object[0]);
        boolean pass = result != null && result.length > 1
                && Boolean.TRUE.equals(result[1]);
        System.exit(pass ? 0 : 1);
    }

    private static void collect(Path p, List<Path> out) throws Exception {
        if (Files.isRegularFile(p)) {
            if (p.toString().endsWith(".lua")) out.add(p);
            return;
        }
        if (Files.isDirectory(p)) {
            try (Stream<Path> s = Files.walk(p)) {
                s.filter(f -> f.toString().endsWith("_spec.lua"))
                 .sorted()
                 .forEach(out::add);
            }
        }
    }

    private static Object[] loadLua(KahluaThread thread, Path file, KahluaTable env)
            throws Exception {
        try (InputStream in = new FileInputStream(file.toFile())) {
            LuaClosure closure = LuaCompiler.loadis(in, file.getFileName().toString(), env);
            Object[] r = thread.pcall(closure, new Object[0]);
            if (r != null && r.length > 0 && Boolean.FALSE.equals(r[0])) {
                throw new RuntimeException("lua error: "
                        + (r.length > 1 ? r[1] : "?"));
            }
            return r;
        }
    }

    private static void installGameConverters(KahluaConverterManager cm) {
        try {
            Class<?> conv = Class.forName("zombie.Lua.KahluaNumberConverter");
            Method install = conv.getMethod("install", KahluaConverterManager.class);
            install.invoke(null, cm);
        } catch (Throwable t) {
            System.err.println("[gate2] KahluaNumberConverter unavailable: " + t);
        }
    }

    public static void installGameEvents(Platform platform, KahluaTable env,
            KahluaConverterManager cm) {
        try {
            Class<?> mgrClass = Class.forName("zombie.Lua.LuaManager");
            java.lang.reflect.Field envF = mgrClass.getField("env");
            envF.set(null, env);
            Class<?> callerClass = Class.forName("se.krka.kahlua.integration.LuaCaller");
            Object caller = callerClass
                    .getConstructor(KahluaConverterManager.class)
                    .newInstance(cm);
            mgrClass.getField("caller").set(null, caller);

            Class<?> mgr = Class.forName("zombie.Lua.LuaEventManager");
            Method reg = mgr.getMethod("register", Platform.class, KahluaTable.class);
            reg.invoke(null, platform, env);
        } catch (Throwable t) {
            while (t instanceof java.lang.reflect.InvocationTargetException
                    && t.getCause() != null) {
                t = t.getCause();
            }
            System.err.println("[gate2] LuaEventManager unavailable: " + t);
        }
    }

    // PZ engine constraints: UIManager.defaultthread must be set or exposed game
    // methods NPE on error; exposeAll() fails partway headless and
    // exposeLikeJavaRecursively leaves typeMap empty, so IsoObject/IsoWorld
    // are pinned into typeMap afterwards.
    private static int installGlobalObject(KahluaConverterManager cm,
            Platform platform, KahluaTable env, KahluaThread thread) {
        try {
            Class<?> go = Class.forName("zombie.Lua.LuaManager$GlobalObject");
            Class<? extends java.lang.annotation.Annotation> annotation =
                    Class.forName("se.krka.kahlua.integration.annotations.LuaMethod")
                            .asSubclass(java.lang.annotation.Annotation.class);
            Class<?> exposerClass;
            Object exposer;
            try {
                exposerClass = Class.forName("zombie.Lua.LuaManager$Exposer");
                exposer = exposerClass
                        .getConstructor(KahluaConverterManager.class,
                                Platform.class, KahluaTable.class)
                        .newInstance(cm, platform, env);
            } catch (Throwable t3) {
                exposerClass = Class.forName(
                        "se.krka.kahlua.integration.expose.LuaJavaClassExposer");
                exposer = exposerClass
                        .getConstructor(KahluaConverterManager.class,
                                Platform.class, KahluaTable.class)
                        .newInstance(cm, platform, env);
            }
            Object instance = go.getConstructor().newInstance();
            Method expose = exposerClass
                    .getMethod("exposeGlobalFunctions", Object.class);
            expose.invoke(exposer, instance);

            try {
                Class.forName("zombie.ui.UIManager")
                        .getField("defaultthread").set(null, thread);
            } catch (Throwable t2) {
                System.err.println("[gate2] UIManager.defaultthread skip: " + t2);
            }
            try {
                Class<?> mgr = Class.forName("zombie.Lua.LuaManager");
                java.lang.reflect.Field expF = mgr.getField("exposer");
                if (expF.get(null) == null) {
                    expF.set(null, exposer);
                }
            } catch (Throwable t2) {
                System.err.println("[gate2] LuaManager.exposer skip: " + t2);
            }

            try {
                exposerClass.getMethod("exposeAll").invoke(exposer);
                System.out.println("[gate2] Exposer.exposeAll: complete");
            } catch (Throwable t4) {
                while (t4 instanceof java.lang.reflect.InvocationTargetException
                        && t4.getCause() != null) {
                    t4 = t4.getCause();
                }
                System.err.println("[gate2] Exposer.exposeAll partial (kept): "
                        + t4.getClass().getName() + ": " + t4.getMessage());
            }

            try {
                Object tmObj = Class.forName(
                        "se.krka.kahlua.integration.expose.LuaJavaClassExposer")
                        .getField("typeMap").get(exposer);
                @SuppressWarnings("unchecked")
                java.util.Map<Object, Object> typeMap =
                        (java.util.Map<Object, Object>) tmObj;
                String[][] pins = {
                    { "IsoObject", "zombie.iso.IsoObject" },
                    { "IsoWorld", "zombie.iso.IsoWorld" },
                };
                for (String[] pin : pins) {
                    if (!typeMap.containsKey(pin[0])) {
                        typeMap.put(pin[0], Class.forName(pin[1]));
                    }
                }
            } catch (Throwable t5) {
                System.err.println("[gate2] instanceof typeMap pin skip: " + t5);
            }
            int count = 0;
            for (Method m : go.getDeclaredMethods()) {
                int mods = m.getModifiers();
                if (java.lang.reflect.Modifier.isStatic(mods)
                        && java.lang.reflect.Modifier.isPublic(mods)
                        && m.isAnnotationPresent(annotation)) {
                    count++;
                }
            }
            System.out.println("[gate2] GlobalObject exposed: " + count
                    + " LuaMethod methods (bounded to GlobalObject)");
            return count;
        } catch (Throwable t) {
            while (t instanceof java.lang.reflect.InvocationTargetException
                    && t.getCause() != null) {
                t = t.getCause();
            }
            System.err.println("[gate2] GlobalObject exposure unavailable: " + t);
            return 0;
        }
    }

    private static String norm(Path p) {
        return p.toAbsolutePath().normalize().toString().replace('\\', '/');
    }

    private static String unquote(String s) {
        s = s.trim();
        s = s.replaceAll("^\"+", "").replaceAll("\"+$", "").trim();
        return s;
    }

    private static void addModPathDirs(List<String> out, String value) {
        for (String dir : value.split(";", -1)) {
            dir = unquote(dir);
            if (!dir.isEmpty()) {
                out.add(dir);
            }
        }
    }

    private static boolean isBareModId(String tok) {
        return !tok.isEmpty() && !tok.equals(".") && !tok.equals("..")
                && !tok.contains("/") && !tok.contains(":")
                && !tok.contains("\"");
    }

    private static boolean dirExists(Path d) {
        if (!Files.isDirectory(d)) {
            return false;
        }
        try (Stream<Path> s = Files.list(d)) {
            return s.findAny().isPresent();
        } catch (Exception e) {
            return false;
        }
    }

    private static String numericVersionDir(Path base) {
        String best = null;
        long bestN = Long.MIN_VALUE;
        try (Stream<Path> s = Files.list(base)) {
            for (Path c : s.sorted().collect(java.util.stream.Collectors.toList())) {
                String name = c.getFileName().toString();
                if (name.matches("\\d+")) {
                    long n;
                    try {
                        n = Long.parseLong(name);
                    } catch (NumberFormatException nfe) {

                        continue;
                    }
                    if (best == null || n > bestN) {
                        best = name;
                        bestN = n;
                    }
                }
            }
        } catch (Exception e) {
            return null;
        }
        return best;
    }

    private static Layout resolveModLayout(Path base) {
        Layout l = new Layout();
        if (Files.isRegularFile(base.resolve("mod.info"))) {
            l.dirs.add(base);
            l.info = base.resolve("mod.info");
            return l;
        }
        String versionDir = numericVersionDir(base);
        Path versionInfo = versionDir != null
                ? base.resolve(versionDir).resolve("mod.info") : null;
        boolean hasVersionInfo = versionInfo != null && Files.isRegularFile(versionInfo);
        if (Files.isRegularFile(base.resolve("common").resolve("mod.info"))
                || hasVersionInfo) {
            if (dirExists(base.resolve("common"))) {
                l.dirs.add(base.resolve("common"));
            }
            if (versionDir != null && dirExists(base.resolve(versionDir))) {
                l.dirs.add(base.resolve(versionDir));
            }
            l.info = hasVersionInfo ? versionInfo
                    : base.resolve("common").resolve("mod.info");
            return l;
        }
        l.info = null;
        return l;
    }

    private static List<String> listLuaFiles(Path dir) {
        List<String> out = new ArrayList<>();
        try (Stream<Path> s = Files.walk(dir)) {
            s.filter(f -> f.toString().endsWith(".lua"))
             .forEach(f -> out.add(norm(f)));
        } catch (Exception e) {

        }
        return out;
    }

    private static List<String> readModInfoDeps(Path info) {
        List<String> deps = new ArrayList<>();
        if (info == null || !Files.isRegularFile(info)) {
            return deps;
        }
        try {
            for (String line : Files.readAllLines(info,
                    java.nio.charset.StandardCharsets.ISO_8859_1)) {
                line = line.replaceAll("\\s+$", "");
                if (line.startsWith("require=")) {
                    for (String tok : line.substring(8).replace("\\", "").split(",")) {
                        if (!tok.isEmpty()) {
                            deps.add(tok);
                        }
                    }
                }
            }
        } catch (Exception e) {

            System.out.println("PZ_MOD: mod.info unreadable in '"
                    + norm(info) + "': " + e);
        }
        return deps;
    }

    private static ModInfo loadMod(Path base, String ctx, List<String> modPathArg,
            KahluaThread thread, KahluaTable env) {
        Layout layout = resolveModLayout(base);
        if (!layout.found()) {
            System.out.println("PZ_MOD: mod.info not found in '" + norm(base) + "'");
            return null;
        }

        ModInfo mod = new ModInfo(base, ctx);
        java.util.Set<String> seen = new java.util.LinkedHashSet<>();

        for (String sub : SUBS) {
            for (Path d : layout.dirs) {
                Path cand = d.resolve("media").resolve("lua").resolve(sub);
                String cn = norm(cand);
                if (dirExists(cand) && seen.add(cn)) {
                    mod.roots.add(cn);
                }
            }
        }

        String[] loadSubs = "server".equals(ctx)
                ? new String[] { "shared", "server" }
                : new String[] { "shared", "client", "server" };
        for (String sub : loadSubs) {
            for (Path d : layout.dirs) {
                Path dir = d.resolve("media").resolve("lua").resolve(sub);
                if (dirExists(dir)) {
                    List<String> batch = listLuaFiles(dir);
                    batch.sort(String.CASE_INSENSITIVE_ORDER);
                    mod.loadFiles.addAll(batch);
                }
            }
        }

        if (dirExists(base.resolve("TESTS"))) {
            mod.specDirs.add(norm(base.resolve("TESTS")));
        }

        mod.deps.addAll(readModInfoDeps(layout.info));
        for (String tok : mod.deps) {
            if (!isBareModId(tok)) {

                System.out.println("PZ_MOD: dependency '" + tok
                        + "' is not a bare mod ID, skipped");
                continue;
            }
            Layout dep = null;
            for (String searchDir : modPathArg) {
                String sdir = searchDir.replace('\\', '/').replaceAll("/+$", "");
                if (sdir.isEmpty()) {
                    continue;
                }
                dep = resolveModLayout(Path.of(sdir, tok).toAbsolutePath().normalize());
                if (dep.found()) {
                    break;
                }
                dep = null;
            }
            if (dep != null) {
                for (String sub : SUBS) {
                    for (Path d : dep.dirs) {
                        Path cand = d.resolve("media").resolve("lua").resolve(sub);
                        String cn = norm(cand);
                        if (dirExists(cand) && seen.add(cn)) {
                            mod.roots.add(cn);
                        }
                    }
                }
            } else {
                System.out.println("PZ_MOD: dependency '" + tok
                        + "' not found in PZ_MOD_PATH");
            }
        }

        recordModInfo(thread, env, mod);

        for (String f : mod.loadFiles) {
            try {
                loadLua(thread, Path.of(f), env);
            } catch (Throwable t) {
                System.out.println("MOD LOAD FAIL " + f + ": " + t);
                System.exit(1);
            }
        }
        return mod;
    }

    private static String luaStr(String s) {
        return "'" + s.replace("\\", "\\\\").replace("'", "\\'")
                .replace("\n", "\\n").replace("\r", "\\r") + "'";
    }

    private static void joinLuaList(StringBuilder sb, List<String> items) {
        for (int i = 0; i < items.size(); i++) {
            if (i > 0) {
                sb.append(",");
            }
            sb.append(luaStr(items.get(i)));
        }
    }

    private static void recordModInfo(KahluaThread thread, KahluaTable env,
            ModInfo mod) {
        StringBuilder sb = new StringBuilder();
        sb.append("__PZ_MOD_INFO = { base = ").append(luaStr(norm(mod.base)));
        sb.append(", ctx = ").append(luaStr(mod.ctx));
        sb.append(", roots = {");
        joinLuaList(sb, mod.roots);
        sb.append("}, load_files = {");
        joinLuaList(sb, mod.loadFiles);
        sb.append("}, deps = {");
        joinLuaList(sb, mod.deps);
        sb.append("}, spec_dirs = {");
        joinLuaList(sb, mod.specDirs);
        sb.append("} }\n");
        try (InputStream in = new ByteArrayInputStream(
                sb.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8))) {
            LuaClosure closure = LuaCompiler.loadis(in, "=pzmodinfo", env);
            Object[] r = thread.pcall(closure, new Object[0]);
            if (r != null && r.length > 0 && Boolean.FALSE.equals(r[0])) {
                System.err.println("[gate2] __PZ_MOD_INFO record failed: "
                        + (r.length > 1 ? r[1] : "?"));
            }
        } catch (Exception e) {
            System.err.println("[gate2] __PZ_MOD_INFO record failed: " + e);
        }
    }
}
