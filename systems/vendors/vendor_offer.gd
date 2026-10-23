class_name VendorOffer
extends RefCounted
## One item a vendor is selling right now. Spec: docs/systems/vendors.md.

var item_id: StringName = &""
var price: int = 0
## How many are left. -1 = unlimited.
var remaining: int = -1


static func make(item_id_: StringName, price_: int, remaining_: int) -> VendorOffer:
	var offer := VendorOffer.new()
	offer.item_id = item_id_
	offer.price = price_
	offer.remaining = remaining_
	return offer
