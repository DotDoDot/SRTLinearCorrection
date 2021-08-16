# SRTLinearCorrection
Linear correction for SRT files using perl

Usage:
perl LinearCorrectionSRT.pl filename.srt '00:00:00,000' '00:00:00,000' '00:00:00,000' '00:00:00,000'

Provide two sets of timestamps where you notice the video desync and have correct timestamps for those two desyncs. 
Best to use a timestamp from the beginning of the movie and one close to the end of the movie.
