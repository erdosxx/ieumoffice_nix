<!--
repo: edwardkim/rhwp
issue: 8626
kind: comment
-->
같은 원인의 **공개 재현 문서**와, 이 이슈에서 시험한 고침이 다루지 못하는 경우를 덧붙입니다. 함께 쓸 수 있는 일반화한 고침도 제안합니다.

### 공개 재현 문서

pblsketch/ieumoffice#490 에 올라온 서울회생법원 빈 서식(재판기록 열람·복사 등 신청서, 17,920 bytes, 개인 정보 없음)입니다.
[table-cell-width-sample.zip](https://github.com/user-attachments/files/34670620/table-cell-width-sample.zip)

- 표 1개, 18행 × 9열, 셀 48개, 글자처럼 취급. 표 개체 폭은 **41,563HU**입니다.
- 0열부터 마지막 열까지 병합 없이 닫히는 행(7, 8, 11~16행)의 칸 폭 합은 **모두 46,971HU**입니다. 표 개체 폭보다 5,408HU(13%) 넓습니다.
- 15행의 ‘영 수 인’ 칸(`r=15, c=4, cs=1, w=8846`)이 4번 열을 혼자 차지하는 유일한 칸입니다.

rhwp v0.9.0(`c9095c5f`)에서는 `invalid_declared_width_rows()` 가 닫힌 행을 모두 무효로 보고, `resolve_column_widths()` 2단계가 3~6행의 `c4+1 = 8,065HU` 를 4·5번 열에 똑같이 나눕니다. 그래서 ‘영 수 인’ 칸이 4,032HU(53.77px)로 그려지고 ‘인’이 칸 밖으로 나갑니다. 한컴은 칸 폭대로 8,846HU 로 그립니다(한글 2024 화면은 ieumoffice#490, 한글 2020 Linux 에서도 같습니다).

### #8626 에서 시험한 고침이 다루지 못하는 이유

시험한 고침은 병합하지 않은 칸을 가진 **모든** 행이 무효일 때만(`all_rows_wider`) 무효 처리를 풉니다. 이 문서는 세로 병합에 덮여 닫히지 않는 행(1, 3~6, 10행)에도 병합하지 않은 칸이 있습니다. 그 행들은 무효가 아니므로 `all_rows_wider` 가 거짓이 되어 고침이 걸리지 않습니다. 열 폭 근거가 한꺼번에 사라지는 #8626 과 달리, 근거가 하나뿐인 경계(4|5)만 사라지는 경우입니다.

### 한컴이 그리는 방식(측정)

닫힌 행의 칸 폭을 행마다 누적한 경계는 서로 단조 증가하지 않습니다. 15행의 4|5 경계는 35,158HU 이고, 0·2행의 6번 경계는 34,377HU 로 그보다 왼쪽입니다. 한글 2020 Linux 화면에서 재면 2행 6번 경계는 약 34,570HU, 15행 4|5 경계는 약 35,100HU 입니다(화면 125%, 측정 오차 ±1px). 즉 한컴은 **각 행을 자기 칸 폭 누적 경계로** 그립니다. 하한 해로 경계를 단조 증가시키는 `contradictory_column_boundaries_hu`(웹한글기안기 측정)와 달리, 행마다 경계가 엇갈려도 그대로 그립니다.

### 제안하는 고침

**닫힌 행들이 서로 같은 폭에 합의하고 그 폭이 표 개체 폭보다 허용치 넘게 넓으면, 낡은 것은 개체 폭이다** 라고 봅니다.

- `Table::stale_width_consensus_hu()` / `effective_width_hu()` 를 둡니다. 닫힌 행(기존 무효 판정과 같은 정의: `row_span == 1` 칸으로 0열부터 마지막 열까지 빈틈없이)의 합이 모두 허용치(`max(폭/100, 열 수)`) 안에서 같고, 그 합이 개체 폭보다 허용치를 넘게 클 때만 그 합을 돌려줍니다. 아니면 개체 폭을 돌려줍니다.
- 합의가 있으면 `invalid_declared_width_rows()` 는 빈 집합을 돌려줍니다. 행끼리는 모순이 없으므로 근거에서 뺄 이유가 없습니다.
- `resolve_column_widths()` 의 목표 폭과 `build_row_col_x()` 의 `target_total` 이 `effective_width_hu()` 를 씁니다. 그러면 #5590 경로(자기 구획을 완결한 행은 선언 구획 그대로)가 합의한 행들을 각자의 경계로 그립니다. 한컴과 같습니다.
- 한 행만 넓은 손상 표처럼 행끼리 합이 다르면 합의가 없으므로 종전 판정 그대로입니다.

TAC 표에만 적용되고 세로 병합이 하나라도 있으면 포기하는 `closed_inline_grid_width_hu`(“개체의 `sz`만 바꾼 독립 한컴 Print 대조군에서도 셀 그리드 폭은 유지된다”)를 일반화한 것에 가깝습니다. #8626 의 표(모든 행 43,200HU, 개체 42,520HU)도 합의 조건에 들어가서, 한컴처럼 43,200HU 로 그려질 것으로 예상합니다. 다만 그 문서가 없어서 직접 확인하지는 못했습니다.

### 확인한 것

rhwp v0.9.0(crates.io 패키지, `c9095c5f` 와 파일 단위로 동일) + IeumOffice 의 엔진 패치 위에서 확인했습니다.

- **재현 문서:** 15행 ‘영 수 인’ 칸이 8,846HU(117.9px)가 되고, 세 글자가 칸 안에 고르게 놓입니다. 11행은 자기 저장값(6,917HU)으로 0.1px 움직이고, 다른 칸은 그대로입니다. render tree, SVG, IeumOffice 편집 화면과 인쇄 렌더에서 모두 확인했습니다.
- **회귀:** `samples/` 최상위의 HWP/HWPX 375개와 로컬 문서 7개의 render tree(전 쪽, 모든 노드 좌표)를 고침 전후로 바이트 비교했습니다. 바뀐 문서는 재현 문서 1개뿐입니다. 고침 전후 모두 실패한 4개(암호 문서 3, 600초 넘는 `issue2063_huge_cellbreak_table.hwp` 1)는 같습니다.
- **확인하지 못한 것:** 저장소의 `tests/` 회귀 묶음은 돌리지 못했습니다. 아래 diff 는 `devel`(`4c876654`, 2026-11-11)에 `git apply` 로 그대로 적용되지만(한 hunk 가 10줄 이동), `devel` 에서 빌드해 돌려 보지는 않았습니다.

<details>
<summary>diff (devel 4c876654 기준)</summary>

```diff
diff --git a/src/model/table.rs b/src/model/table.rs
index 98ad0a8..9c6b286 100644
--- a/src/model/table.rs
+++ b/src/model/table.rs
@@ -934,11 +934,95 @@ impl Table {
         &self,
         storage: &S,
     ) -> Result<std::collections::BTreeSet<u16>, S::Error> {
-        let tolerance =
-            (u64::from(self.common.width) / 100).max(usize::from(self.col_count).max(1) as u64);
+        // [#8626] 닫힌 행이 모두 같은 폭에 합의하면 낡은 것은 표 개체 폭이다. 그 행들은
+        // 서로 맞는 공유 격자이므로 근거에서 빼지 않는다.
+        if self.stale_width_consensus_hu_with_storage(storage)?.is_some() {
+            return Ok(std::collections::BTreeSet::new());
+        }
+        let tolerance = self.declared_width_tolerance_hu();
         self.declared_width_rows_exceeding_with_storage(tolerance, storage)
     }
 
+    fn declared_width_tolerance_hu(&self) -> u64 {
+        (u64::from(self.common.width) / 100).max(usize::from(self.col_count).max(1) as u64)
+    }
+
+    /// [#8626] 표 개체 폭(`common.width`)이 칸 폭과 따로 낡은 표에서 행이 합의한 표 폭(HU).
+    ///
+    /// 한컴이 다른 형식에서 옮겨 저장하거나 개체 크기만 갱신하지 않은 문서는, 칸 폭은 맞는데
+    /// 표 개체 폭만 작게 남는다(워드 변환 표: 개체 42,520 / 모든 행 43,200, 서울회생법원
+    /// 서식: 개체 41,563 / 닫힌 행 모두 46,971). 한컴은 이런 표를 칸 폭대로, 행마다 자기
+    /// 칸 폭 누적 경계로 그린다. 반면 개체 폭을 기준으로 삼으면 닫힌 행이 모두 "표보다 넓은
+    /// 무효 행"이 되어 열 폭 근거가 사라지고, 그 열만 정하던 칸이 이웃과 균등 분배된다.
+    ///
+    /// 다음을 모두 만족할 때만 `Some(합의 폭)` 이다(그 밖은 종전 해석을 그대로 쓴다).
+    /// - 0열부터 마지막 열까지 빈틈없이 닫히는 행(병합하지 않은 행 기준)이 하나 이상 있다.
+    /// - 그 행들의 칸 폭 합이 모두 같다(허용치 안).
+    /// - 그 합이 표 개체 폭보다 허용치를 넘게 넓다 — 행 하나만 넓은 손상 표와 달리, 행끼리는
+    ///   모순이 없고 개체 폭만 어긋난다.
+    pub(crate) fn stale_width_consensus_hu(&self) -> Option<u32> {
+        match self.stale_width_consensus_hu_with_storage(&crate::storage::Unbounded) {
+            Ok(value) => value,
+            Err(never) => match never {},
+        }
+    }
+
+    fn stale_width_consensus_hu_with_storage<S: crate::storage::Storage>(
+        &self,
+        storage: &S,
+    ) -> Result<Option<u32>, S::Error> {
+        let col_count = usize::from(self.col_count);
+        if col_count == 0 || self.common.width == 0 {
+            return Ok(None);
+        }
+        let mut by_row = std::collections::BTreeMap::<u16, Vec<&Cell>>::new();
+        for cell in &self.cells {
+            if cell.row < self.row_count && cell.row_span == 1 {
+                if !by_row.contains_key(&cell.row) {
+                    storage.tree_entry::<u16, Vec<&Cell>>()?;
+                }
+                storage.push(by_row.entry(cell.row).or_default(), cell)?;
+            }
+        }
+        let mut min_total = u64::MAX;
+        let mut max_total = 0u64;
+        for (_, mut cells) in by_row {
+            storage.bytes(std::mem::size_of_val(cells.as_slice()))?;
+            cells.sort_by_key(|cell| cell.col);
+            let mut next_col = 0usize;
+            let mut total = 0u64;
+            let mut complete = !cells.is_empty();
+            for cell in cells {
+                let start = usize::from(cell.col);
+                let end = start.saturating_add(usize::from(cell.col_span));
+                if cell.col_span == 0 || start != next_col || end > col_count {
+                    complete = false;
+                    break;
+                }
+                total = total.saturating_add(u64::from(cell.width));
+                next_col = end;
+            }
+            if complete && next_col == col_count {
+                min_total = min_total.min(total);
+                max_total = max_total.max(total);
+            }
+        }
+        let tolerance = self.declared_width_tolerance_hu();
+        if max_total == 0
+            || max_total - min_total > tolerance
+            || max_total.saturating_sub(u64::from(self.common.width)) <= tolerance
+        {
+            return Ok(None);
+        }
+        Ok(u32::try_from(max_total).ok())
+    }
+
+    /// 표를 그릴 폭(HU): 행이 합의한 폭이 있으면 그 값, 아니면 표 개체 폭.
+    pub(crate) fn effective_width_hu(&self) -> u32 {
+        self.stale_width_consensus_hu()
+            .unwrap_or(self.common.width)
+    }
+
     pub(crate) fn declared_width_rows_exceeding_with_storage<S: crate::storage::Storage>(
         &self,
         tolerance: u64,
diff --git a/src/renderer/layout/border_rendering.rs b/src/renderer/layout/border_rendering.rs
index cca0f9c..51c8ebe 100644
--- a/src/renderer/layout/border_rendering.rs
+++ b/src/renderer/layout/border_rendering.rs
@@ -275,8 +275,11 @@ fn build_fallback_row_col_x(
         base_rx[c + 1] = base_rx[c] + col_widths[c] + cell_spacing;
     }
 
-    let target_total = if table.common.width > 0 {
-        hwpunit_to_px(table.common.width as i32, dpi) * width_scale
+    // [#8626] 개체 폭만 낡은 표는 행이 합의한 폭이 표 외곽이다. 그 폭으로 닫히는 행은
+    // 아래 #5590 경로에서 자기 칸 폭 누적 경계로 그려진다(한컴과 같다).
+    let effective_width = table.effective_width_hu();
+    let target_total = if effective_width > 0 {
+        hwpunit_to_px(effective_width as i32, dpi) * width_scale
     } else {
         base_rx.last().copied().unwrap_or(0.0)
     };
diff --git a/src/renderer/layout/table_layout.rs b/src/renderer/layout/table_layout.rs
index 973c3eb..ab698cf 100644
--- a/src/renderer/layout/table_layout.rs
+++ b/src/renderer/layout/table_layout.rs
@@ -5176,7 +5176,8 @@ impl LayoutEngine {
                 }
             }
         }
-        let declared_width = inline_grid_width.unwrap_or(table.common.width);
+        // [#8626] 개체 폭만 낡은 표는 행이 합의한 폭을 표 폭으로 본다.
+        let declared_width = inline_grid_width.unwrap_or(table.effective_width_hu());
         let target_width = if declared_width > 0 {
             (hwpunit_to_px(declared_width as i32, self.dpi) * width_scale
                 - hwpunit_to_px(i32::from(table.cell_spacing), self.dpi) * (col_count + 1) as f64)
```

</details>

필요하면 PR 로 올리고 테스트도 덧붙이겠습니다.
