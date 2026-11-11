<!--
repo: pblsketch/ieumoffice
title: [HWP] Linux에서 글꼴을 바꾸면 편집기가 멈춤 — 렌더러가 열린 파일 한도(1024)에 걸려 FontData.blob()이 교착됨
-->
### App

Other (HWP 편집기 — 템플릿 목록에 HWP 항목이 없어 Other로 선택했습니다)

### Version and OS

0.12.12 (공식 ieumoffice_0.12.12_amd64.deb, Electron 43.7.6 / 소스 빌드도 동일), Linux x86_64 (NixOS, X11), 설치 글꼴 약 3,300개

### What happened?

HWP 편집기에서 글꼴을 바꾸면 편집기 창 전체가 멈춥니다. 마우스와 키보드에 반응하지 않고, 스스로 풀리지 않습니다. 보통 글꼴을 한 번은 바꿀 수 있고, 두 번째에 멈춥니다(공식 deb 빌드에서는 첫 번째에 멈추기도 했습니다). 멈춘 동안 CPU 사용은 0이고, 콘솔에도 오류가 없습니다.

**재현 방법**

설치된 글꼴이 많은(수천 개) Linux 데스크톱이 조건입니다. 데스크톱 세션은 보통 프로그램을 열린 파일 soft 한도 1024로 시작합니다.

1. `.hwp` 파일을 엽니다.
2. 툴바의 글꼴 상자 → **시스템 글꼴**을 열고 목록을 훑어보거나, 선택한 글자에 글꼴을 한두 번 바꿔 적용합니다.
3. 편집기가 멈춥니다.

설치 글꼴이 적거나, `ulimit -Sn 524288` 같이 한도를 올린 셸에서 실행하면 재현되지 않습니다. 반대로 `ulimit -Sn 1024`로 실행하면 확실하게 재현됩니다.

**원인 분석**

1. **렌더러의 열린 파일이 정확히 1024개입니다.** 멈춘 HWP 렌더러 프로세스는 파일 디스크립터 1,024개를 쓰고 있었고, 그중 976개가 글꼴 파일이었습니다. Chromium은 브라우저 프로세스의 한도만 hard 한도까지 올리고, 렌더러는 그 전에 fork된 zygote에서 나오기 때문에 세션의 soft 한도 1024를 그대로 물려받습니다.

   | 프로세스 | 열린 파일 soft 한도 |
   |---|---|
   | 브라우저 (main) | 524288 |
   | HWP 렌더러 | **1024** |

2. **글꼴 파일을 모두 엽니다.** rhwp-studio의 `src/core/local-fonts.ts`에서 `detectLocalFonts()`는 `queryLocalFonts()`로 설치된 모든 글꼴을 받아, `collectLocalFontRecords()`가 글꼴마다 `readSfntFontNames()`를 부릅니다. 이 함수는 `name` 테이블을 읽으려고 `fontData.blob()`을 호출합니다. 글꼴 목록의 미리 보기와 CanvasKit용 글꼴 데이터(`readLocalFontBytesBatch()` 등) 읽기도 글꼴 파일을 엽니다. 설치 글꼴이 수천 개면 렌더러가 금방 1024에 닿습니다.

3. **한도에 닿으면 교착됩니다.** 그다음 `FontData.blob()`은 Blob 등록을 위해 브라우저 프로세스에 동기 Mojo 호출(`BlobRegistry::Register`)을 보내는데, 핸들을 만들 수 없어 응답이 오지 않고 렌더러 메인 스레드가 영원히 기다립니다. 멈춘 렌더러에 gdb를 붙이고 Electron 43.7.6 공식 Breakpad 심볼로 해석한 메인 스레드 스택은 아래(Logs)와 같습니다.

**확인한 해결 방법**

실행 전에 soft 한도를 hard 한도로 올리면 해결됩니다. 패키지(Nix) 실행 스크립트에 아래를 넣고 확인했습니다.

```sh
ulimit -Sn "$(ulimit -Hn)" 2>/dev/null || true
exec /opt/IeumOffice/ieumoffice "$@"
```

`ulimit -Sn 1024` 셸에서 시작해도 렌더러 한도가 524288이 되고, 시스템 글꼴 목록 전체를 훑어 열린 파일이 1,300~1,500개가 되어도 멈추지 않았습니다. 7~55 MB 글꼴(Noto CJK, 함초롬바탕 확장B 등)의 `blob()`도 정상입니다.

**제안**

- **패키지:** deb/rpm/AppImage의 실행 경로(`.desktop`의 `Exec`, AppImage의 `AppRun`)를 위처럼 soft 한도를 올리는 작은 실행 스크립트로 바꿉니다. 메인 프로세스 JS에서는 이미 zygote가 fork된 뒤라 늦습니다.
- **rhwp-studio(근본 원인):** 글꼴 이름을 읽으려고 모든 글꼴의 `blob()`을 여는 대신, 가능하면 `FontData`의 `family` / `fullName` / `postscriptName`을 쓰고, 한글 이름이 필요한 글꼴만 읽거나 결과를 캐시해서 열린 파일 수를 줄입니다. 필요하면 rhwp(edwardkim/rhwp)에도 전달해 주세요.

### Logs / screenshots

멈춘 HWP 렌더러의 메인 스레드 (Electron 43.7.6, Breakpad 심볼로 해석):

```
pthread_cond_wait
base::WaitableEvent::WaitManyImpl
base::WaitableEvent::WaitMany
mojo::WaitSet::State::Wait
mojo::SyncHandleRegistry::Wait
mojo::SyncEventWatcher::SyncWatch
mojo::SequenceLocalSyncEventWatcher::SyncWatch
mojo::InterfaceEndpointClient::SendMessageWithResponder
mojo::InterfaceEndpointClient::AcceptWithResponder
mojo::internal::SendMojoMessage
blink::mojom::blink::BlobRegistryProxy::Register
blink::BlobDataHandle::BlobDataHandle
blink::BlobDataHandle::Create
blink::FontMetadata::BlobImpl
blink::FontMetadata::blob(blink::ScriptState*)
...
base::RunLoop::Run
content::RendererMain
```

- 렌더러 메인 스레드: `futex(FUTEX_WAIT_BITSET_PRIVATE, …, timeout=NULL)`. 다른 렌더러 스레드, 브라우저 프로세스, GPU 프로세스는 모두 대기(유휴) 상태입니다.
- 렌더러 `/proc/<pid>/limits`: `Max open files 1024 524288`
- 렌더러 열린 파일 1,024개 중 976개가 글꼴 파일 (`…/share/fonts/…`)
