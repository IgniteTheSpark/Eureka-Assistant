import { Route, Routes } from "react-router-dom";

import { CategoryList } from "@/components/library/CategoryList";
import { CategoryDetail } from "@/components/library/CategoryDetail";

/**
 * LibraryPage — root container for the "资产库" surface.
 *
 * Two states:
 *   - /library              → CategoryList (primary, iOS-Files style)
 *   - /library/:skillName   → CategoryDetail (drill-down for one type)
 *
 * Nested routes are declared here so React Router DOM scopes them under
 * /library; the App.tsx router uses /library/* to delegate.
 */
export function LibraryPage() {
  return (
    <Routes>
      <Route index element={<CategoryList />} />
      <Route path=":skillName" element={<CategoryDetail />} />
    </Routes>
  );
}
