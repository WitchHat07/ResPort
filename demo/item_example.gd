@tool
extends Resource
class_name ItemExample

# Your parameters
@export var display_name: String
@export var cost: int
@export var category: String

#region ResPort Interface
# Whatever you intend to make manageble by ResPort must be clearer defined in your Script.
# When ResPort calls to your Script to serialize it into a CSV line, these are the methods that get called.
## Tells ResPort what fields to include in header for this Resource
func to_csv_header() -> Array[String]:
	return ["display_name", "cost", "category"]
## Serializes this object int field values that index-match this Resource's defined headers
func to_csv_fields() -> Array[String]:
	return [
		display_name,
		str(cost),
		category
	]
## Applies field values loaded from a CSV that index-match this Resource's defined headers
func apply_csv_fields(values: Array[String]):
	if values.size() < 3:
		print("ResPort: Invalid CSV data for Item")
		return
	display_name = values.get(0)
	cost = int(values.get(1))
	category = values.get(2)
#endregion
