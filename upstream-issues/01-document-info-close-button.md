<!--
repo: pblsketch/ieumoffice
title: [HWP] 파일 → 문서 정보 창의 [닫기] 버튼이 동작하지 않음 (TypeError: this.onConfirm is not a function)
-->
### App

Other (HWP 편집기 — 템플릿 목록에 HWP 항목이 없어 Other로 선택했습니다)

### Version and OS

0.12.12 (공식 ieumoffice_0.12.12_amd64.deb, 그리고 v0.12.12 태그 소스 빌드), Linux x86_64 (NixOS)

### What happened?

HWP 편집기에서 **파일 → 문서 정보**(Ctrl+Q, I)를 열면 문서 통계 창이 뜹니다. 창 아래의 **[닫기]** 버튼을 눌러도 창이 닫히지 않고, 제목 줄의 **×** 버튼으로만 닫힙니다.

**재현 방법**

1. 아무 `.hwp` / `.hwpx` 파일을 HWP 편집기로 엽니다.
2. 메뉴 **파일 → 문서 정보**를 엽니다 (명령 `ieum:document-info`).
3. 창 아래 **[닫기]** 버튼을 누릅니다.

- **기대한 동작:** 창이 닫힘
- **실제 동작:** 아무 반응이 없고, 콘솔에 아래 예외가 남음 (× 버튼은 정상 동작)

공식 deb 빌드와 소스 빌드 모두에서 같고, 현재 `main`의 코드도 같습니다.

**원인**

`apps/hwp/studio-plugin/document-info.mjs`의 `DocumentInfoDialog`는 rhwp의 `ModalDialog`를 상속해서, `show()`에서 기본 대화상자의 **확인(primary) 버튼** 글자를 `닫기`로 바꾸고 취소 버튼을 지웁니다. 그런데 `onConfirm()`을 정의하지 않습니다. `ModalDialog`는 확인 버튼을 이렇게 연결합니다 (빌드된 studio 번들 기준):

```js
o.addEventListener("click", () => { this.onConfirm() !== false && this.hide() })
```

그래서 [닫기]를 누르면 `this.onConfirm()`에서 예외가 나고 `hide()`까지 가지 못합니다. × 버튼은 `this.hide()`를 바로 부르므로 정상입니다. 같은 폴더의 다른 대화상자(`FormatCopyDialog`, `CellPasteDialog`, `PageNumberDialog`, `HanjaDialog`)는 모두 `onConfirm()`이 있고, 빠진 것은 `DocumentInfoDialog` 하나입니다.

**제안하는 수정** (`apps/hwp/studio-plugin/document-info.mjs`, `class DocumentInfoDialog`, 현재 `main`에 `git apply`로 바로 적용됩니다)

```diff
--- a/apps/hwp/studio-plugin/document-info.mjs
+++ b/apps/hwp/studio-plugin/document-info.mjs
@@ -396,6 +396,11 @@
       setTimeout(() => this.fill(), 0)
     }
 
+    // [닫기] is the base dialog's confirm button: just close.
+    onConfirm() {
+      return true
+    }
+
     fill() {
       if (this.filled) return
       this.filled = true
```

이 한 줄짜리 수정을 패키지(Nix)에 적용해서, [닫기]로 창이 닫히고 예외가 없어지는 것을 공식 deb 빌드와 소스 빌드 모두에서 확인했습니다.

### Logs / screenshots

```
TypeError: this.onConfirm is not a function
    at HTMLButtonElement.<anonymous> (genoffice-app://hwp/studio/assets/index-D4xIq1Zt.js:80:1772)
```
