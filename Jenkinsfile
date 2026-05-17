build_type = 'Release'
archs_to_build = []
archs_to_pack = []

def do_init(list) {
    withCredentials([string(credentialsId: 'trace-sentry-dsn', variable: 'TRACE_SENTRY_DSN')]) {
      pwsh '.\\build.ps1 -Config -VcpkgPath C:\\vcpkg -SentryDsn $Env:TRACE_SENTRY_DSN'
    }
    pwsh ".\\build.ps1 -Init"
    list.each { item ->
      echo "Doing init for ${item}"
      try {
        pwsh ".\\build.ps1 -Vcpkg -Latest -Arch ${item}"
        archs_to_build.add( item )
      } catch (err) {
        currentBuild.result='UNSTABLE'
        echo 'Exception occurred: ' + err.toString()
        echo "Failed vcpkg for ${item}"
      }
    }

    if( archs_to_build.size() == 0 )
    {
      currentBuild.result='FAILURE'
    }
}

def do_build(arches) {
    pwsh "Get-ChildItem .out -Exclude '*-pdb' | Remove-Item -Recurse -ErrorAction SilentlyContinue"
    
    withCredentials([string(credentialsId: 'trace-amplitude-key', variable: 'AMPLITUDE_API_KEY')]) {
      arches.each { arch ->
        echo "Doing build for ${arch} ${build_type}"
        try {
          if(params.TRAIN != 'nightly') {
            pwsh ".\\build.ps1 -Build -Arch ${arch} -BuildConfigName ${params.BUILD_CONFIG}"
          }
          else {
            pwsh ".\\build.ps1 -Build -Latest -Arch ${arch} -BuildType ${build_type}"
          }
          archs_to_pack.add( arch )
        } catch (err) {
          currentBuild.result='UNSTABLE'
          echo 'Exception occurred: ' + err.toString()
          echo "Failed build for ${arch} ${build_type}"
        }
      }
    }
    
    if( archs_to_pack.size() == 0 )
    {
      currentBuild.result='FAILURE'
    }
}

def do_package(arches, lite) {
    arches.each { arch ->
      echo "Doing package for ${arch} ${build_type}"

      withCredentials([azureServicePrincipal('trace-azuresigntool')]) {
        try {
          $signString = ' -Sign -SignAKV $True -AKVUrl "https://trace-codesign.vault.azure.net/" -AKVTenantId $Env:AZURE_TENANT_ID -AKVAppId $Env:AZURE_CLIENT_ID -AKVAppSecret $Env:AZURE_CLIENT_SECRET -AKVCertName "' + params.AKV_KEY_NAME + '"'

          if( lite ) {
              echo "Building lite package"
              $cmd = ".\\build.ps1 -Package -Arch ${arch} -BuildConfigName ${params.BUILD_CONFIG} -Lite -Prepare \$True" + $signString
          } else {
              echo "Packaging full release"
              $cmd = ".\\build.ps1 -Package -Arch ${arch} -BuildConfigName ${params.BUILD_CONFIG} -DebugSymbols -SentryArtifact \$True -Prepare \$True" + $signString
          }
          
          pwsh  $cmd
        } catch (err) {
          currentBuild.result='UNSTABLE'
          echo 'Exception occurred: ' + err.toString()
          echo "Failed package for ${arch} ${build_type}"
        }
      }

    }
}

pipeline {
    agent { label 'msvc' }
    options {
      timestamps ()
      skipDefaultCheckout true
    }
    environment {
        LC_ALL = 'C'
        VCPKG_BINARY_SOURCES='nuget,trace,readwrite'
    }
    parameters {
        booleanParam(name: 'LITE_PKG_ONLY', defaultValue: false, description: 'Skip building the full installer')
        booleanParam(name: 'CLEAN_WS', defaultValue: false, description: 'Clean workspace')
        choice(name: 'TRAIN', choices: ['nightly', 'release', 'testing'], description: '')
        text(name: 'BUILD_CONFIG', defaultValue: 'trace-nightly', description: '')
        booleanParam(name: 'BUILD_ARM64', defaultValue: true, description: 'Build arm64')
        booleanParam(name: 'BUILD_X64', defaultValue: true, description: 'Build 64-bit')
        booleanParam(name: 'BUILD_X86', defaultValue: false, description: 'Build 32-bit')
        text(name: 'AKV_KEY_NAME', defaultValue: 'Trace2025SigningKey', description: 'Name of code sign cert in Azure Key Vault')
    }


    stages {
      stage ('Checkout') {
          steps {
              script {
                if (params.CLEAN_WS == true) {
                  cleanWs()
                }
              }
              checkout([$class: 'GitSCM', branches: [[name: '*/master']],
              doGenerateSubmoduleConfigurations: false,
              extensions: [],
              submoduleCfg: [],
              userRemoteConfigs: [[credentialsId: '',
              url: 'https://gitlab.com/trace/packaging/trace-win-builder.git']]])
          }
      }

      stage ('Init toolchain') {
          steps {
              script {
                archs = []

                if( params.BUILD_X64 ) {
                  archs.add( 'x64' )
                }

                if( params.BUILD_X86 ) {
                  archs.add( 'x86' )
                }

                if( params.BUILD_ARM64 ) {
                  archs.add( 'arm64' )
                }

                do_init(archs)
              }
          }
      }

      stage ('Build Trace') {
          steps {
              script {
                do_build(archs_to_build)
              }
          }
      }

      stage ('Package Lite') {
          when {
              expression {
                  return params.TRAIN == 'nightly' || params.TRAIN == 'testing';
              }
          }
          steps {
              script {
                do_package(archs_to_pack, true)
              }
              dir (".out") {
                archiveArtifacts allowEmptyArchive: false, artifacts: 'trace*.exe', caseSensitive: true, defaultExcludes: true, fingerprint: true, onlyIfSuccessful: true
                archiveArtifacts allowEmptyArchive: false, artifacts: 'commit-hash', caseSensitive: true, defaultExcludes: true, fingerprint: true, onlyIfSuccessful: true
                bat "DEL /Q /F \"trace*-lite.exe\"" 
              }
          }
      }

      stage ('Package Full') {
        when {
            expression {
                return !params.LITE_PKG_ONLY
            }
        }
        steps {
            script {
              do_package(archs_to_pack, false)
            }
            dir (".out") {
              archiveArtifacts allowEmptyArchive: false, artifacts: 'trace*.exe', caseSensitive: true, defaultExcludes: true, fingerprint: true, onlyIfSuccessful: true
              archiveArtifacts allowEmptyArchive: false, artifacts: 'trace*-pdbs.zip', caseSensitive: true, defaultExcludes: true, fingerprint: true, onlyIfSuccessful: true
              archiveArtifacts allowEmptyArchive: false, artifacts: 'trace*-sentry.zip', caseSensitive: true, defaultExcludes: true, fingerprint: true, onlyIfSuccessful: true
              archiveArtifacts allowEmptyArchive: false, artifacts: 'trace*-sentry-src.zip', caseSensitive: true, defaultExcludes: true, fingerprint: true, onlyIfSuccessful: true
              archiveArtifacts allowEmptyArchive: false, artifacts: 'commit-hash', caseSensitive: true, defaultExcludes: true, fingerprint: true, onlyIfSuccessful: true
              bat "DEL /Q /F \"trace*.exe\"" 
              bat "DEL /Q /F \"trace*.zip\"" 
            }
        }
      }
    }
    
    post {
      always {
          node('master') {
            script {
                  // to get mailer to behave well
                  if (currentBuild.result == null) {
                      currentBuild.result = 'SUCCESS'    
                  }
            }
            step([$class: 'Mailer',
                  notifyEveryUnstableBuild: true,
                  recipients: "hello@buildwithtrace.com",
                  sendToIndividuals: false])
          }
        }
    }
}
