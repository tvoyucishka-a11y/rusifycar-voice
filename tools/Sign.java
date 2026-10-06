import com.android.apksig.ApkSigner;
import com.android.apksig.ApkVerifier;
import java.io.*;
import java.nio.file.*;
import java.security.*;
import java.security.cert.*;
import java.security.spec.PKCS8EncodedKeySpec;
import java.util.*;

public class Sign {
  public static void main(String[] a) throws Exception {
    if (a[0].equals("verify")) {
      ApkVerifier.Result r = new ApkVerifier.Builder(new File(a[1])).build().verify();
      System.out.println("verified=" + r.isVerified() + " v1=" + r.isVerifiedUsingV1Scheme() + " v2=" + r.isVerifiedUsingV2Scheme() + " v3=" + r.isVerifiedUsingV3Scheme());
      for (ApkVerifier.IssueWithParams e : r.getErrors()) System.out.println("ERR " + e);
      for (X509Certificate c : r.getSignerCertificates()) System.out.println("cert sha256=" + hex(MessageDigest.getInstance("SHA-256").digest(c.getEncoded())));
      return;
    }
    PrivateKey key = KeyFactory.getInstance("RSA").generatePrivate(new PKCS8EncodedKeySpec(Files.readAllBytes(Paths.get(a[2]))));
    X509Certificate cert = (X509Certificate) CertificateFactory.getInstance("X.509").generateCertificate(new FileInputStream(a[3]));
    ApkSigner.SignerConfig sc = new ApkSigner.SignerConfig.Builder("PLATFORM", key, Collections.singletonList(cert)).build();
    new ApkSigner.Builder(Collections.singletonList(sc)).setInputApk(new File(a[0])).setOutputApk(new File(a[1]))
        .setV1SigningEnabled(true).setV2SigningEnabled(true).setV3SigningEnabled(false).build().sign();
    System.out.println("signed " + a[1]);
  }
  static String hex(byte[] b) { StringBuilder s = new StringBuilder(); for (byte x : b) s.append(String.format("%02x", x)); return s.toString(); }
}
