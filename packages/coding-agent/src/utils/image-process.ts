/**
 * Inline image attachment policy.
 *
 * Image attachments are refused: with the Photon image processing library
 * removed, images can no longer be converted or resized to fit inline
 * provider limits. Both the read tool and @file CLI argument handling emit
 * this message in place of an image attachment.
 */
export const IMAGE_ATTACHMENT_REFUSED_MESSAGE =
	"[Image omitted: inline image attachments are not supported.]";
