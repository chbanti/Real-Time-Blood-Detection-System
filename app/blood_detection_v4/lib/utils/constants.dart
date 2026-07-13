// Detection model - 640x640
const int inputWidth = 640;    // Changed from 224 to 640
const int inputHeight = 640;   // Changed from 224 to 640

// Segmentation model - 224x224 (keep as is)
const int segInputWidth = 224;
const int segInputHeight = 224;

const double confidenceThreshold = 0.35;
const double iouThreshold = 0.45;
const double liveConfidenceThreshold = 0.5;