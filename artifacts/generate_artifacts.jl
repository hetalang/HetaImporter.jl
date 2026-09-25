using ArtifactUtils
using Pkg.Artifacts

const HETA_COMPILER_RELEASE = "v0.12.2-beta.0"

const artifacts_toml = joinpath(@__DIR__, "..", "Artifacts.toml")

# heta-compiler does not publish an x86_64 (Intel) macOS build, only aarch64 (Apple Silicon).
platforms = [
  Artifacts.Platform("x86_64", "linux"),
  Artifacts.Platform("aarch64", "linux"),
  Artifacts.Platform("x86_64", "windows"),
  Artifacts.Platform("aarch64", "macos")
]

rm(artifacts_toml; force = true)

for platform in platforms

  os  = platform.tags["os"]

  arch = platform.tags["arch"]
  if arch == "x86_64"
    arch = "x64"
  elseif arch == "aarch64"  
    arch = "arm64"
  else
    error("Unsupported architecture: $arch")
  end
    
  # tmp use aarch64-macos artifact for x86_64-macos hosts too
  if os == "macos" && arch == "x64"
    @warn "Using aarch64-macos artifact for x86_64-macos host (Rosetta)."
    arch = "arm64"
  end

  url = "https://github.com/hetalang/heta-compiler/releases/download/$HETA_COMPILER_RELEASE/heta-compiler-$os-$arch.tar.gz"

  println("Adding artifact for $platform")

  try
    add_artifact!(
        artifacts_toml,
        "heta_app",
        url;
        platform,
        force = true,
        lazy = false,
    )
  catch e
    error("Failed to add artifact for $platform from $url: $e")
  end
end
