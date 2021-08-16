#!/usr/bin/perl
use strict;
use warnings;
use 5.010;
use POSIX;
use Math::Round;
use Data::Dumper;

#https://www.speechpad.com/captions/srt
#Read in the SRT file:
#Each subtitle group consists of three parts:
#1. the subtitle number (a sequential number beginning with 1)
#2. two timecodes indicating when the subtitle should appear and disappear (start and end times)
#3. the text of the subtitle
#Example:
# 1
# 00:00:00,498 --> 00:00:02,827
# - Here's what I love most
# about food and diet.
#
#Timecodes have the following format:
#
#hours:minutes:seconds,milliseconds
#example
#01:07:32,053 --> 01:07:35,500

#Ensure 5 params are passed
if($#ARGV + 1 != 5) {
	die "missing params\nUSAGE: $0 filename.srt '00:00:00,000' '00:00:00,000' '00:00:00,000' '00:00:00,000'";
}

#check that an srt file has been passed in.
my $file = $ARGV[0]?$ARGV[0]:die "no file passed, please provide a file"; #expected file name format: filename.srt
my @filename = split('[.]',$file);
if(!($filename[1] eq "srt" || $filename[1] eq "SRT")) {
	die "file format is not srt";
}

#helper function to split a time stamp into an array.
sub splitTimeToArray {
	my ($time) = @_;
	return [split('[:,]', $time)]
}

#Holds the four time stamps passed through the command line arguments
my @times;

for(my $i = 1; $i < 5; $i++) {
#check for errors in time stamp format
	if ( !($ARGV[$i] =~ m/^'((?:-)*)(\d{2}:\d{2}:\d{2},\d{3})'$/gm) ){ 
		die "your time passed in does not match format 00:00:00,000"
	}
	push (@times, splitTimeToArray($2));#expected shift time format: 00:00:00,000
}

#helper function to print a time stamp from an array.
sub print_time {
	my (@time) = @_;
	return $time[0][0] . ":" . $time[0][1] . ":" . $time[0][2] . "," . $time[0][3];
}

#conversion function from a time array to milliseconds scalar.
sub convertTimeToMilliseconds {
	my (@timeToConvert) = @_;
	my $milliseconds = $timeToConvert[0][3];
	$milliseconds += $timeToConvert[0][2] * 1000; #seconds to milliseconds
	$milliseconds += $timeToConvert[0][1] * 60 * 1000; #Minutes to milliseconds
	$milliseconds += $timeToConvert[0][0] * 60 * 60 * 1000; #Hours to milliseconds
	return $milliseconds;
}

#conversion function from a milliseconds scalar to time array.
sub convertMillisecondsToTimes {
	my ($millisecondToConvert) = @_;
	return [
		sprintf("%02d", floor(($millisecondToConvert / (60 * 60 * 1000)) % 99)), #hours
		sprintf("%02d", floor(($millisecondToConvert / (60 * 1000)) % 60)), #minutes
		sprintf("%02d", floor(($millisecondToConvert / 1000) % 60)), #seconds
		sprintf("%03d", $millisecondToConvert % 1000) #milliseconds
	];
}

#check that the two beginning time stamp arguments actually
#exist inside the passed in srt file.
sub checkTimestampsExist {
	my ($timeStamp1, $timeStamp2, @content) = @_;
	my $flag1 = 0;
	my $flag2 = 0;
	for(@content) {
		@$_[1] =~ m/(^\d+:\d+:\d+,\d+)\s+-->\s+\d+:\d+:\d+,\d+$/gm;
		#check if the first time stamp matches either of the
		#beginning time stamps passed in as arguments.
		my $match = $1;
		if(print_time($timeStamp1) eq $match) {
			$flag1 = 1;
		}
		if(print_time($timeStamp2) eq $match) {
			$flag2 = 1;
		}
	}
	return ($flag1,$flag2);
}

#Read file text into srt_file_str
open my $input, '<', $file or die "can't open $file: $!";
my $srt_file_str;
while (<$input>) {

    chomp;
    # do something with $_
	$srt_file_str .= $_ . "\n";
}
close $input or die "can't close $file: $!";

#create an array of triplets splitting each subtitle
#into its three parts:
#1) subtitle number
#2) two timecodes
#3) text of the subtitle
my @content;
while($srt_file_str =~ m/(^\d+$)\s*(^\d+:\d+:\d+,\d+\s+-->\s+\d+:\d+:\d+,\d+$)\s*((?:.(?!^\d+$))*)/sgm) {
	push(@content, [$1,$2,$3]);
}

#Check to make sure first and second times exist in the srt
my ($timeStamp1Startflag, $timeStamp2Startflag) = checkTimestampsExist($times[0], $times[2], @content);

#Check the beginning time stamp flags to both be true
if(!($timeStamp1Startflag and $timeStamp2Startflag)) {
	die "can't find beginning time stamps " . print_time($times[0]) . " and " . print_time($times[2]);
}

#Calculate the 'm' and 'b' of the Linear equation y = m * x + b
sub calc_m_b {
	my ($timeStamp1Start, $timeStamp1End, $timeStamp2Start, $timeStamp2End) = @_;
	my $m = ($timeStamp2End - $timeStamp1End) / ($timeStamp2Start - $timeStamp1Start);
	my $b = $timeStamp2End - $m * $timeStamp2Start;
	return $m, $b;
}

#Convert a time stamp array to milliseconds then apply
#the linear correction, then convert back to array.
sub linear_correction {
	my ($x_time_array, $m, $b) = @_;
	my $x_msec = convertTimeToMilliseconds($x_time_array); # change from 00:00:00,000 to milliseconds
	#Apply the linear correction
	my $x_correct_msec = round($m * $x_msec + $b);
	my $x_correct_array = convertMillisecondsToTimes($x_correct_msec); # change from milliseconds to 00:00:00,000
	return $x_correct_array;
}

#Function which applies the linear correction to the entire
#srt file.
sub linear_correct_subs {
	my ($m, $b) = @_;
	#foreach subtitle start & end timestamp
	for(@content) {
		my $string = @$_[1];
		$string =~ m/^(\d+:\d+:\d+,\d+)\s+-->\s+(\d+:\d+:\d+,\d+)$/sgm;
		my $timeArray1 = splitTimeToArray($1);
		my $timeArray2 = splitTimeToArray($2);
		
		my $correctTimeDelta1 = linear_correction($timeArray1, $m, $b);
		my $correctTimeDelta2 = linear_correction($timeArray2, $m, $b);
		
		#linear correction in place.
		@$_[1] = print_time($correctTimeDelta1) . " --> " . print_time($correctTimeDelta2);
	}
}

#Calculate the m and b of the linear correction equation using
#the 4 time stamps passed in via the command line.
my ($m, $b) = calc_m_b(
	convertTimeToMilliseconds($times[0]), 
	convertTimeToMilliseconds($times[1]), 
	convertTimeToMilliseconds($times[2]), 
	convertTimeToMilliseconds($times[3]));
	
#Apply the linear correction to all the subtitles:
linear_correct_subs($m, $b);

#Open/Close a new file and save the corrected srt time stamps.
my $outputFilename = $filename[0] . "-resync.srt";
open my $fh, '>', $outputFilename or die "Cannot open $outputFilename: $!";

# Loop over the array and print to output file
foreach (@content)
{
	foreach(@$_) {
		print $fh "$_\n"; # Print each entry in our array to the file
	}
}
close $fh or die "can't close $fh: $!";