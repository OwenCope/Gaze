# Local data

- `spoof-detection/`: the original Roboflow CreateML export, including its notices.
- `spoof-subset/`: the existing subset; its image links point into `spoof-detection/`.
- `evaluation/`: space for local evaluation data.

These directories are excluded from source control and are not app resources.
The app uses the models in `Resources/`; building Gaze does not need this data.
Dataset preparation and evaluation commands are in [Tools/ModelLab](../Tools/ModelLab/README.md).
