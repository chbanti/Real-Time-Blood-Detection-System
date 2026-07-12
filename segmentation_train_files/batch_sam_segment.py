import torch
from segment_anything import sam_model_registry, SamPredictor
import cv2
import numpy as np
import os
import json
import time
from datetime import datetime

# ============================================================
#  CONFIG
# ============================================================
DATA_REVIEW_DIR = r"D:\Taha Projects\AI Projects\Blood_trail Project\Dataset\filtered\data_review"
SAM_CHECKPOINT  = r"D:\Taha Projects\AI Projects\Blood_trail Project\Blood_proj\sam_vit_b_01ec64.pth"
OUTPUT_DIR      = r"D:\Taha Projects\AI Projects\Blood_trail Project\Dataset\SAM_output"

SPLITS          = ["train", "valid", "test"]
BLOOD_CLASS     = 0
MODEL_TYPE      = "vit_b"

# Minimum box size to send to SAM (skip tiny/noisy boxes)
MIN_BOX_W    = 10
MIN_BOX_H    = 10
MIN_BOX_AREA = 200
# ============================================================

# ---------- Output sub-folders — split wise ----------
# masks and overlays now organized by split
coco_dir = os.path.join(OUTPUT_DIR, "coco")
os.makedirs(coco_dir, exist_ok=True)

# ---------- Device ----------
device = "cuda" if torch.cuda.is_available() else "cpu"
print(f"Using device: {device}")

# ---------- Load SAM ----------
print("Loading SAM model...")
sam = sam_model_registry[MODEL_TYPE](checkpoint=SAM_CHECKPOINT)
sam.to(device=device)
predictor = SamPredictor(sam)
print("SAM loaded!\n")

# ---------- COCO structure ----------
coco_output = {
    "info": {
        "description": "BloodTrail AI — SAM-generated segmentation masks",
        "date_created": datetime.now().strftime("%Y/%m/%d"),
    },
    "licenses": [],
    "images": [],
    "annotations": [],
    "categories": [{"id": 1, "name": "blood", "supercategory": "none"}]
}

image_id      = 1
annotation_id = 1

# ---------- Stats ----------
stats = {
    "total":              0,
    "processed":          0,
    "skipped_no_label":   0,
    "skipped_no_blood":   0,
    "skipped_tiny_boxes": 0,
    "errors":             0
}

start_time = time.time()

# ---------- Main Loop ----------
for split in SPLITS:
    images_dir = os.path.join(DATA_REVIEW_DIR, split, "images")
    labels_dir = os.path.join(DATA_REVIEW_DIR, split, "labels")

    # Output folders per split — no prefix in filenames
    masks_dir   = os.path.join(OUTPUT_DIR, split, "masks")
    overlay_dir = os.path.join(OUTPUT_DIR, split, "overlays")
    os.makedirs(masks_dir,   exist_ok=True)
    os.makedirs(overlay_dir, exist_ok=True)

    if not os.path.exists(images_dir):
        print(f"Skipping {split}: folder not found at {images_dir}")
        continue

    image_files = [f for f in os.listdir(images_dir)
                   if f.lower().endswith(('.jpg', '.jpeg', '.png'))]

    print(f"\n{'='*55}")
    print(f"Processing {split}: {len(image_files)} images")
    print(f"{'='*55}")

    for idx, img_file in enumerate(image_files):
        stats["total"] += 1
        img_name = os.path.splitext(img_file)[0]

        print(f"[{split}] {idx+1}/{len(image_files)} | {img_file[:55]}", end="\r")

        img_path   = os.path.join(images_dir, img_file)
        label_path = os.path.join(labels_dir, img_name + ".txt")

        # Skip if no label file
        if not os.path.exists(label_path):
            stats["skipped_no_label"] += 1
            continue

        # Read blood boxes from label
        boxes = []
        with open(label_path, "r") as f:
            for line in f.readlines():
                line = line.strip()
                if not line:
                    continue
                parts = line.split()
                if len(parts) < 5:
                    continue
                cls = int(float(parts[0]))
                if cls == BLOOD_CLASS:
                    x, y, bw, bh = map(float, parts[1:5])
                    boxes.append((x, y, bw, bh))

        # Skip if no blood boxes
        if not boxes:
            stats["skipped_no_blood"] += 1
            continue

        # Read image
        image = cv2.imread(img_path)
        if image is None:
            print(f"\nWarning: Cannot read {img_path}")
            stats["errors"] += 1
            continue

        h, w = image.shape[:2]
        image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)

        try:
            predictor.set_image(image_rgb)

            combined_mask   = np.zeros((h, w), dtype=np.uint8)
            valid_box_count = 0

            for (x, y, bw, bh) in boxes:
                x1 = int((x - bw / 2) * w)
                y1 = int((y - bh / 2) * h)
                x2 = int((x + bw / 2) * w)
                y2 = int((y + bh / 2) * h)

                x1, y1 = max(0, x1), max(0, y1)
                x2, y2 = min(w, x2), min(h, y2)

                box_w    = x2 - x1
                box_h    = y2 - y1
                box_area = box_w * box_h

                if box_w < MIN_BOX_W or box_h < MIN_BOX_H or box_area < MIN_BOX_AREA:
                    stats["skipped_tiny_boxes"] += 1
                    continue

                box_np = np.array([x1, y1, x2, y2])
                masks, scores, _ = predictor.predict(
                    box=box_np,
                    multimask_output=False
                )

                combined_mask = np.logical_or(combined_mask, masks[0]).astype(np.uint8)
                valid_box_count += 1

            if valid_box_count == 0:
                stats["skipped_no_blood"] += 1
                continue

            # Save binary mask — no prefix, original image name
            mask_filename  = f"{img_name}_mask.png"
            mask_save_path = os.path.join(masks_dir, mask_filename)
            cv2.imwrite(mask_save_path, combined_mask * 255)

            # Save overlay — no prefix
            overlay = image.copy()
            overlay[combined_mask == 1] = (0, 0, 200)
            blended = cv2.addWeighted(image, 0.6, overlay, 0.4, 0)
            overlay_filename = f"{img_name}_overlay.jpg"
            cv2.imwrite(os.path.join(overlay_dir, overlay_filename), blended)

            # COCO annotation
            coco_output["images"].append({
                "id":        image_id,
                "file_name": img_file,
                "split":     split,
                "width":     w,
                "height":    h
            })

            contours, _ = cv2.findContours(
                combined_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
            )

            segmentation = []
            for contour in contours:
                if contour.size >= 6:
                    seg = contour.flatten().tolist()
                    segmentation.append(seg)

            if segmentation:
                x_coords = [pt for seg in segmentation for pt in seg[0::2]]
                y_coords = [pt for seg in segmentation for pt in seg[1::2]]
                bbox_x   = min(x_coords)
                bbox_y   = min(y_coords)
                bbox_w   = max(x_coords) - bbox_x
                bbox_h   = max(y_coords) - bbox_y

                coco_output["annotations"].append({
                    "id":           annotation_id,
                    "image_id":     image_id,
                    "category_id":  1,
                    "segmentation": segmentation,
                    "area":         int(combined_mask.sum()),
                    "bbox":         [bbox_x, bbox_y, bbox_w, bbox_h],
                    "iscrowd":      0
                })
                annotation_id += 1

            image_id           += 1
            stats["processed"] += 1

        except Exception as e:
            print(f"\nError on {img_file}: {e}")
            stats["errors"] += 1
            continue

# ---------- Save COCO JSON ----------
coco_json_path = os.path.join(coco_dir, "coco_annotations.json")
with open(coco_json_path, "w") as f:
    json.dump(coco_output, f, indent=2)

# ---------- Final Report ----------
total_time = time.time() - start_time
print(f"\n\n{'='*55}")
print(f"BATCH SEGMENTATION COMPLETE")
print(f"{'='*55}")
print(f"Total images found:            {stats['total']}")
print(f"Successfully processed:        {stats['processed']}")
print(f"Skipped (no label file):       {stats['skipped_no_label']}")
print(f"Skipped (no blood / all tiny): {stats['skipped_no_blood']}")
print(f"Tiny boxes skipped:            {stats['skipped_tiny_boxes']}")
print(f"Errors:                        {stats['errors']}")
print(f"Time taken:                    {total_time/60:.1f} minutes")
print(f"\nOutputs saved to: {OUTPUT_DIR}")
print(f"  train/masks/    -> train binary masks")
print(f"  train/overlays/ -> train visual verification")
print(f"  valid/masks/    -> valid binary masks")
print(f"  valid/overlays/ -> valid visual verification")
print(f"  test/masks/     -> test binary masks")
print(f"  test/overlays/  -> test visual verification")
print(f"  coco/           -> coco_annotations.json")