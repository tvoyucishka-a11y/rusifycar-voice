import brut.androlib.mod.SmaliMod;
import com.android.tools.smali.dexlib2.Opcodes;
import com.android.tools.smali.dexlib2.writer.builder.DexBuilder;
import com.android.tools.smali.dexlib2.writer.io.FileDataStore;
import java.io.File;
import java.nio.file.*;
import java.util.*;
import java.util.stream.*;

public class Assemble {
  public static void main(String[] a) throws Exception {
    String dir = a[0], out = a[1]; int api = Integer.parseInt(a[2]);
    DexBuilder db = new DexBuilder(new Opcodes(api, 0));
    List<File> files;
    try (Stream<Path> s = Files.walk(Paths.get(dir))) {
      files = s.filter(p -> p.toString().endsWith(".smali")).map(Path::toFile)
               .sorted().collect(Collectors.toList());
    }
    for (File f : files) {
      if (!SmaliMod.assembleSmaliFile(f, db, api)) throw new RuntimeException("assemble failed: " + f);
    }
    db.writeTo(new FileDataStore(new File(out)));
    System.out.println("assembled " + files.size() + " files -> " + out);
  }
}
