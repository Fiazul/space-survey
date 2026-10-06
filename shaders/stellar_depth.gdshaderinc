varying vec4 stellar_clip_position;
void vertex() {
	stellar_clip_position = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = stellar_clip_position;
	POSITION.z = max(POSITION.z, CLIP_SPACE_FAR * POSITION.w);
}
float stellar_depth() {
	float clip_depth = stellar_clip_position.z / stellar_clip_position.w;
	return clamp((clip_depth-CLIP_SPACE_FAR)/(1.0-CLIP_SPACE_FAR), 1e-6, 1.0);
}
