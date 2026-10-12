import { spawnSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
const directory = process.env.MESH_EVIDENCE_DIR ?? "docs/evidence/publishing-security";
const scan = JSON.parse(await readFile(path.join(directory, "image-security.json"), "utf8"));
const decisions = [];
for (const name of ["api", "web", "partner"]) {
  const image = scan.images[name]?.image;
  if (!/^sha256:[a-f0-9]{64}$/.test(image ?? "")) throw new Error("Exact local image required.");
  const result = spawnSync(
    "docker",
    [
      "run",
      "--rm",
      "--network",
      "none",
      "--read-only",
      "--entrypoint",
      "sh",
      image,
      "-c",
      "dpkg-query -W -f='${binary:Package} ${Version} ${db:Status-Abbrev}\\n'; printf '\\nCOMPONENT_PATHS\\n'; find /usr -path '*/Archive/Tar.pm' -o -name '*minizip*' -o -name 'systemd-homed*' -o -name 'infocmp'",
    ],
    { encoding: "utf8", windowsHide: true, timeout: 30000 },
  );
  if (result.error || result.status !== 0) throw result.error ?? new Error("Inventory failed.");
  await writeFile(path.join(directory, name + "-inventory.txt"), result.stdout);
  const paths = result.stdout.split("COMPONENT_PATHS")[1] ?? "";
  const rows = JSON.parse(await readFile(path.join(directory, "trivy-" + name + ".json"), "utf8"));
  for (const vulnerability of (rows.Results ?? []).flatMap((row) => row.Vulnerabilities ?? [])) {
    const id = vulnerability.VulnerabilityID;
    let status = "under_investigation",
      reason =
        "Vulnerable source package is present. Available mitigations do not by themselves establish non-applicability.";
    if (
      id === "CVE-2023-45853" &&
      vulnerability.PkgName === "zlib1g" &&
      vulnerability.InstalledVersion === "1:1.2.13.dfsg-1" &&
      !paths.includes("minizip")
    ) {
      status = "not_affected";
      reason =
        "Debian bookworm does not build vulnerable contrib/minizip into zlib binary packages; exact inventory contains no MiniZip component.";
    }
    if (id === "CVE-2026-9538" && !paths.includes("Archive/Tar.pm")) {
      status = "not_affected";
      reason =
        "The Archive::Tar module required by this finding is absent from the exact runtime inventory; perl-base alone does not supply it.";
    }
    if (
      id === "CVE-2026-16742" &&
      ["libsystemd0", "libudev1"].includes(vulnerability.PkgName) &&
      !paths.includes("systemd-homed")
    ) {
      status = "not_affected";
      reason =
        "Upstream affected component is the systemd-homed service. The image contains shared libraries, not that component.";
    }
    decisions.push({
      image_role: name,
      image,
      vulnerability: id,
      package: vulnerability.PkgName,
      version: vulnerability.InstalledVersion,
      status,
      reason,
      checked_at: new Date().toISOString(),
      expires_at: "2026-11-07T00:00:00Z",
      source: "https://security-tracker.debian.org/tracker/" + id,
      inventory: name + "-inventory.txt",
      action:
        status === "not_affected"
          ? "Re-evaluate after any image/package change; preserve raw finding."
          : "Require upstream patched runtime or separately approved, scoped risk decision before external release.",
    });
  }
}
const report = {
  schema_version: 1,
  checked_at: new Date().toISOString(),
  decisions,
  totals: Object.fromEntries(
    ["not_affected", "under_investigation"].map((status) => [
      status,
      decisions.filter((row) => row.status === status).length,
    ]),
  ),
  strict_release_gate_changed: false,
  approved_external_release: false,
  scope:
    "Engineering applicability review for three exact application/simulator images. No broad ignore, no acceptance of remaining findings, no signed VEX/provenance claim. Infrastructure raw scans are separate.",
};
await writeFile(path.join(directory, "applicability.json"), JSON.stringify(report, null, 2) + "\n");
console.log(JSON.stringify({ totals: report.totals, strict_release_gate_changed: false }, null, 2));
