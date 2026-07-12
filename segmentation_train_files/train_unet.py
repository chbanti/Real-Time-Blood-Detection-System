import os
import cv2
import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader
import segmentation_models_pytorch as smp
from torch.optim import AdamW
from torch.optim.lr_scheduler import CosineAnnealingLR
import time
from datetime import datetime

# ============================================================
# CONFIG
# ============================================================
DATASET_DIR  = r"D:\Taha Projects\AI Projects\Blood_trail Project\Dataset\blood_data"
MASKS_DIR    = r"D:\Taha Projects\AI Projects\Blood_trail Project\Dataset\SAM_output"
OUTPUT_DIR   = r"D:\Taha Projects\AI Projects\Blood_trail Project\Dataset\unet_training"

IMG_SIZE     = 640
BATCH_SIZE   = 16
EPOCHS       = 50
LR           = 1e-4
DEVICE       = "cuda" if torch.cuda.is_available() else "cpu"
# ============================================================

os.makedirs(OUTPUT_DIR, exist_ok=True)
os.makedirs(os.path.join(OUTPUT_DIR, "checkpoints"), exist_ok=True)

# ============================================================
# DATASET
# ============================================================
class BloodSegDataset(Dataset):
    def __init__(self, split, img_size=640):
        self.img_size = img_size
        self.pairs    = []

        images_dir = os.path.join(DATASET_DIR, split, "images")
        masks_dir  = os.path.join(MASKS_DIR,   split, "masks")

        if not os.path.exists(images_dir):
            print(f"Warning: {images_dir} not found")
            return

        for img_file in os.listdir(images_dir):
            if not img_file.lower().endswith(('.jpg', '.jpeg', '.png')):
                continue

            img_name  = os.path.splitext(img_file)[0]
            mask_file = f"{img_name}_mask.png"
            mask_path = os.path.join(masks_dir, mask_file)

            if os.path.exists(mask_path):
                self.pairs.append((
                    os.path.join(images_dir, img_file),
                    mask_path
                ))

        print(f"[{split}] Found {len(self.pairs)} image-mask pairs")

    def __len__(self):
        return len(self.pairs)

    def __getitem__(self, idx):
        img_path, mask_path = self.pairs[idx]

        image = cv2.imread(img_path)
        image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        image = cv2.resize(image, (self.img_size, self.img_size))

        mask = cv2.imread(mask_path, cv2.IMREAD_GRAYSCALE)
        mask = cv2.resize(mask, (self.img_size, self.img_size),
                          interpolation=cv2.INTER_NEAREST)

        image = image.astype(np.float32) / 255.0
        mask  = (mask > 127).astype(np.float32)
        image = np.transpose(image, (2, 0, 1))

        return torch.tensor(image), torch.tensor(mask).unsqueeze(0)

# ============================================================
# MODEL — MobileNetV3 + UNet
# ============================================================
def build_model():
    model = smp.Unet(
        encoder_name="timm-mobilenetv3_small_100",
        encoder_weights="imagenet",
        in_channels=3,
        classes=1,
        activation=None
    )
    return model

# ============================================================
# METRICS
# ============================================================
def dice_score(pred, target, threshold=0.5):
    pred   = (torch.sigmoid(pred) > threshold).float()
    target = target.float()
    intersection = (pred * target).sum()
    return (2.0 * intersection) / (pred.sum() + target.sum() + 1e-8)

def iou_score(pred, target, threshold=0.5):
    pred   = (torch.sigmoid(pred) > threshold).float()
    target = target.float()
    intersection = (pred * target).sum()
    union        = pred.sum() + target.sum() - intersection
    return intersection / (union + 1e-8)

def pixel_accuracy(pred, target, threshold=0.5):
    pred   = (torch.sigmoid(pred) > threshold).float()
    target = target.float()
    correct = (pred == target).sum()
    total   = target.numel()
    return correct / total

# ============================================================
# TRAINING
# ============================================================
def train():
    train_ds = BloodSegDataset("train", IMG_SIZE)
    valid_ds = BloodSegDataset("valid", IMG_SIZE)

    if len(train_ds) == 0:
        print("ERROR: No training pairs found! Check your paths.")
        return

    train_loader = DataLoader(train_ds, batch_size=BATCH_SIZE,
                              shuffle=True,  num_workers=4, pin_memory=True)
    valid_loader = DataLoader(valid_ds, batch_size=BATCH_SIZE,
                              shuffle=False, num_workers=4, pin_memory=True)

    model = build_model().to(DEVICE)
    print(f"Model: MobileNetV3-Small + UNet")
    total_params = sum(p.numel() for p in model.parameters())
    print(f"Total parameters: {total_params:,}\n")

    bce_loss  = nn.BCEWithLogitsLoss()
    dice_loss = smp.losses.DiceLoss(mode="binary", from_logits=True)

    def combined_loss(pred, target):
        return 0.5 * bce_loss(pred, target) + 0.5 * dice_loss(pred, target)

    optimizer = AdamW(model.parameters(), lr=LR, weight_decay=1e-4)
    scheduler = CosineAnnealingLR(optimizer, T_max=EPOCHS, eta_min=1e-6)

    log_path   = os.path.join(OUTPUT_DIR, "training_log.txt")
    best_dice  = 0.0
    best_epoch = 0

    with open(log_path, "w") as log:
        log.write(f"Training started: {datetime.now()}\n")
        log.write(f"Config: img_size={IMG_SIZE}, batch={BATCH_SIZE}, epochs={EPOCHS}, lr={LR}\n\n")
        log.write(f"{'Epoch':>6} | {'Train Loss':>10} | {'Val Loss':>10} | "
                  f"{'Val Dice':>9} | {'Val IoU':>8} | {'Val Acc':>8}\n")
        log.write("-" * 70 + "\n")

    start_time = time.time()

    for epoch in range(1, EPOCHS + 1):
        # ---- TRAIN ----
        model.train()
        train_loss = 0.0

        for images, masks in train_loader:
            images = images.to(DEVICE)
            masks  = masks.to(DEVICE)

            optimizer.zero_grad()
            preds = model(images)
            loss  = combined_loss(preds, masks)
            loss.backward()
            optimizer.step()

            train_loss += loss.item()

        train_loss /= len(train_loader)

        # ---- VALIDATE ----
        model.eval()
        val_loss = 0.0
        val_dice = 0.0
        val_iou  = 0.0
        val_acc  = 0.0

        with torch.no_grad():
            for images, masks in valid_loader:
                images = images.to(DEVICE)
                masks  = masks.to(DEVICE)

                preds     = model(images)
                loss      = combined_loss(preds, masks)
                val_loss += loss.item()
                val_dice += dice_score(preds, masks).item()
                val_iou  += iou_score(preds, masks).item()
                val_acc  += pixel_accuracy(preds, masks).item()

        val_loss /= len(valid_loader)
        val_dice /= len(valid_loader)
        val_iou  /= len(valid_loader)
        val_acc  /= len(valid_loader)

        scheduler.step()

        elapsed = (time.time() - start_time) / 60

        print(f"Epoch {epoch:3d}/{EPOCHS} | "
              f"Train Loss: {train_loss:.4f} | "
              f"Val Loss: {val_loss:.4f} | "
              f"Val Dice: {val_dice:.4f} | "
              f"Val IoU: {val_iou:.4f} | "
              f"Val Acc: {val_acc*100:.2f}% | "
              f"Time: {elapsed:.1f}m")

        with open(log_path, "a") as log:
            log.write(f"{epoch:6d} | {train_loss:10.4f} | {val_loss:10.4f} | "
                      f"{val_dice:9.4f} | {val_iou:8.4f} | {val_acc*100:8.2f}%\n")

        # Save best model
        if val_dice > best_dice:
            best_dice  = val_dice
            best_epoch = epoch
            best_path  = os.path.join(OUTPUT_DIR, "checkpoints", "best_model.pt")
            torch.save({
                "epoch":       epoch,
                "model_state": model.state_dict(),
                "val_dice":    val_dice,
                "val_iou":     val_iou,
                "val_acc":     val_acc,
                "val_loss":    val_loss,
            }, best_path)
            print(f"  >>> Best model saved (Dice: {val_dice:.4f} | Acc: {val_acc*100:.2f}%)")

        # Save checkpoint every 10 epochs
        if epoch % 10 == 0:
            ckpt_path = os.path.join(OUTPUT_DIR, "checkpoints", f"epoch_{epoch}.pt")
            torch.save(model.state_dict(), ckpt_path)

    # ---- FINAL REPORT ----
    total_time = (time.time() - start_time) / 60
    print(f"\n{'='*65}")
    print(f"TRAINING COMPLETE")
    print(f"{'='*65}")
    print(f"Best Dice Score : {best_dice:.4f} at epoch {best_epoch}")
    print(f"Total time      : {total_time:.1f} minutes")
    print(f"Best model saved: {OUTPUT_DIR}/checkpoints/best_model.pt")

    with open(log_path, "a") as log:
        log.write(f"\nBest epoch: {best_epoch} | Best Dice: {best_dice:.4f}\n")
        log.write(f"Total training time: {total_time:.1f} minutes\n")

# ============================================================
# RUN
# ============================================================
if __name__ == "__main__":
    print(f"Device    : {DEVICE}")
    print(f"Image size: {IMG_SIZE}x{IMG_SIZE}")
    print(f"Batch size: {BATCH_SIZE}")
    print(f"Epochs    : {EPOCHS}\n")
    train()
