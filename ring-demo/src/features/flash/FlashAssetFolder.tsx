import { useEffect, useRef } from "react";

import { AssetCard } from "../../components/AssetCard";
import {
  ScrollStack,
  type ScrollStackHandle,
  ScrollStackItem,
} from "../../components/ScrollStack";
import {
  flattenFlashAssetBatches,
  type FlashAssetBatch,
} from "./flash-assets";

export function FlashAssetFolder({
  batches,
}: {
  batches: FlashAssetBatch[];
}) {
  const stackRef = useRef<ScrollStackHandle>(null);
  const latestId = batches[0]?.id;
  const items = flattenFlashAssetBatches(batches);
  const assetCount = items.length;

  useEffect(() => {
    if (latestId) stackRef.current?.scrollToStart();
  }, [latestId]);

  return (
    <section className="flash-asset-folder" aria-label="Generated assets">
      <header className="flash-folder-header">
        <span>ASSET FOLDER</span>
        <strong aria-label={`${assetCount} generated assets`}>{assetCount}</strong>
      </header>

      {batches.length === 0 ? (
        <div className="flash-folder-empty">
          <span aria-hidden="true">＋</span>
          <p>Your assets will gather here.</p>
        </div>
      ) : (
        <ScrollStack
          ref={stackRef}
          itemDistance={128}
          itemStackDistance={26}
          stackPosition="14%"
          scaleEndPosition="7%"
          baseScale={0.9}
          rotationAmount={0}
          blurAmount={0}
          useWindowScroll={false}
          className="flash-folder-stack"
        >
          {items.map((item) => (
            <ScrollStackItem
              key={item.id}
              itemClassName="flash-asset-stack-item"
            >
              <div
                className="flash-asset-entry"
                data-batch-id={item.batchId}
                data-testid={`asset-${item.id}`}
              >
                <AssetCard card={item.card} index={item.batchOrder} />
              </div>
            </ScrollStackItem>
          ))}
        </ScrollStack>
      )}
    </section>
  );
}
