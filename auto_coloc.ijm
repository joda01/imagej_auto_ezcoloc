///
/// \file  	auto_coloc.ijm
/// \author	Joachim Danmayr
/// \date	2020-08-02
/// \brief  Uses the EzColocalization plugin to calculate the
///			colocalzation for vsi images stored in a folder.
///
///         The result is stored to the output folder
///


/// Open dialog to choose input and output folder
#@File(label = "Input directory", style = "directory") input
#@File(label = "Output directory", style = "directory") output
#@String(label = "File suffix", value = ".vsi") suffix

///
/// Seems to be the main :)
///

// inPath, outPath, nrOfChannels, greenChannel, enhanceForC0,enhanceForC1, minParticleSize, colocActive thersholding
SETTING_NR_OF_CHANNELS = 2;
SETTING_GREEN_CHANNEL = 3;
SETTING_ENHANCE_CONTRAST_C0 = 4;
SETTING_ENHANCE_CONTRAST_C1 = 5;
SETTING_MIN_PARTICLE_SIZE = 6;
SETTING_MAX_PARTICLE_SIZE = 7;
SETTING_COLOC_ACTIVE = 8;
SETTING_THERSHOLDING = 9;
settings = openGui();

if (settings[SETTING_COLOC_ACTIVE] == true) {
	allOverStatistic = "file;small;big;coloc;no coloc;GfpOnly;Cy3Only;GfpEvs;Cy3Evs\n";
} else {
	allOverStatistic = "file;small;big;found EVs\n";
}
allOverStatistic = allOverStatistic + processFolder(input);


print("All finished" + allOverStatistic);
File.saveString(allOverStatistic, output + File.separator + "statistic_all_over_final.txt");

///
/// Look recursie for vsi files and process them
///
function processFolder(input) {
	list = getFileList(input);
	list = Array.sort(list);
	retVal = "";
	for (i = 0; i < list.length; i++) {
		if (File.isDirectory(input + File.separator + list[i])) {
			retVal = retVal + processFolder(input + File.separator + list[i]);
		}
		if (endsWith(list[i], suffix)) {
			retVal = retVal + processFile(input, output, list[i]);
		}
	}
	return retVal;
}

///
/// Just a stub function
///
function processFile(input, output, file) {
	print("Processing: " + input + File.separator + file);
	print("Saving to: " + output);
	retVal = openVsiFile(input, output, file);
	return retVal;
}

///
/// Open a two channel VSI and runs the EzColoc algorithm on it
///
function openVsiFile(input, output, file) {


	filename = input + File.separator + file;
	run("Bio-Formats Importer", "open=[" + filename + "] autoscale color_mode=Grayscale rois_import=[ROI manager] specify_range split_channels view=Hyperstack stack_order=XYCZT series_1 c_begin_1=1 c_end_1=2 c_step_1=1");

	list1 = getList("image.titles");

	if (list1.length == 0) {
		print("No image windows are open");
	}
	else {

		gfpIndex = 0;
		cy3Index = 1;

		print("Image windows:");
		for (i = 0; i < list1.length; i++) {

			selectWindow(list1[i]);

			// Red Channel selection
			if (false == endsWith(list1[i], settings[SETTING_GREEN_CHANNEL])) {
				cy3Index = i;
			} else {
				gfpIndex = i;
			}

			if (((true == endsWith(list1[i], "C=0")) && (true == settings[SETTING_ENHANCE_CONTRAST_C0])) ||
				((true == endsWith(list1[i], "C=1")) && (true == settings[SETTING_ENHANCE_CONTRAST_C1]))) {
				run("Enhance Contrast...", "saturated=0.3 normalize");
			}

			run("Subtract Background...", "rolling=4 sliding");
			run("Convolve...", "text1=[1 4 6 4 1\n4 16 24 16 4\n6 24 36 24 6\n4 16 24 16 4\n1 4 6 4 1] normalize");

			//setAutoThreshold("Li dark");
			//setAutoThreshold("MaxEntropy dark");
			setAutoThreshold(""+settings[SETTING_THERSHOLDING]+" dark");
			setOption("BlackBackground", true);
			run("Convert to Mask");
		}

		// Make the sum of both pictures to use this as Cell Identifier input | Add

		imageCalculator("Max create", list1[0], list1[1]);
		selectWindow("Result of " + list1[0]);
		run("Analyze Particles...", "clear add");

		// Measure picture 1
		selectWindow(list1[gfpIndex]);
		roiManager("Measure");
		saveAs("Results", output + File.separator + file + "_gfp.csv");
		run("Clear Results");

		// Measure picture 2
		selectWindow(list1[cy3Index]);
		roiManager("Measure");
		saveAs("Results", output + File.separator + file + "_cy3.csv");
		run("Clear Results");



		// Save a color picture with shows the coloc evs in yellow as well as the red and green channel
		selectWindow(list1[cy3Index]);
		run("Red");
		selectWindow(list1[gfpIndex]);
		run("Green");
		run("Merge Channels...", "c1=["+list1[cy3Index]+"] c2=["+list1[gfpIndex]+"] keep");
		selectWindow("RGB");
		roiManager("Show All");
		saveAs("Jpeg", output + File.separator + file + "_composite.jpg");
		run("Flatten");
		saveAs("Jpeg", output + File.separator + file + "_composite_with_overlay.jpg");

		

		cleanUp();

		if (settings[SETTING_COLOC_ACTIVE] == true) {

			result = calcColocalization(output + File.separator + file + "_gfp.csv", output + File.separator + file + "_cy3.csv", output);
			retVal = file + ";" + toString(result[0]) + ";" + toString(result[1]) + ";" + toString(result[2]) + ";" + toString(result[3]) + ";" + toString(result[4]) + ";" + toString(result[5]) + ";" + toString(result[6]) + ";" + toString(result[7]) + "\n";
			return retVal;
		}
		else {
			result = countEvs(output + File.separator + file + "_gfp.csv", output);
			retVal = file + " GFP;" + toString(result[0]) + ";" + toString(result[1]) + toString(result[2]) +"\n";

			result = countEvs(output + File.separator + file + "_cy3.csv", output);
			retVal = retVal + file + " CY3;" + toString(result[0]) + ";" + toString(result[1]) + toString(result[2]) +"\n";
			return retVal;
		}

	}
}


///
/// Calculates the Coloc coefficent
/// The result is a value in range from [0, 255]
/// 0 is no coloc 255 is maximum coloc.
///
function calcColocalization(resultgfp, resultcy3, output) {

	minAreaSize = settings[SETTING_MIN_PARTICLE_SIZE];
	maxAreaSize = settings[SETTING_MAX_PARTICLE_SIZE];

	read1 = File.openAsString(resultgfp);
	read2 = File.openAsString(resultcy3);

	lines1 = split(read1, "\n");
	lines2 = split(read2, "\n");

	result = "ROI; Area; GFP; CY3; DIFF\n";

	numberOfTooSmallParticles = 0;
	numberOfTooBigParticles = 0;
	numberOfColocEvs = 0;
	numberOfNotColocEvs = 0;
	numberOfGfpOnly = 0;
	numberOfCy3Only = 0;
	numerOfFounfGfp = 0;
	numberOfFoundCy3 = 0;

	// First line is header therefore start with 1
	for (i = 1; i < lines1.length; i++) {

		linegfp = split(lines1[i], ",");
		linecy3 = split(lines2[i], ",");
		if (linegfp[1] > minAreaSize) {
			if(linegfp[1] < maxAreaSize){

				a = parseFloat(linegfp[2]);
				b = parseFloat(linecy3[2]);

				// Coloc algorithm
				sub = abs(255 - abs(a - b));

				// Calculate the sum of coloc EVs
				if (sub > 0) {
					numberOfColocEvs++;
				} else {
					numberOfNotColocEvs++;
					// Take all values which do not coloc
					// All with 255 in gfp = gfp only
					// All with 255 in cy3 = cy3 only

					if (255 == linegfp[2]) {
						numberOfGfpOnly++;
					}
					if (255 == linecy3[2]) {
						numberOfCy3Only++;
					}
				}

				//
				// Count the found EVs
				//
				if (a > 0) {
					numerOfFounfGfp++;
				}
				if (b > 0) {
					numberOfFoundCy3++;
				}

				result = result + linegfp[0] + ";" + linegfp[1] + ";" + linegfp[2] + ";" + linecy3[2] + ";" + toString(sub) + "\n";
			}else{
				numberOfTooBigParticles++;
			}
		} else {
			numberOfTooSmallParticles++;
		}
	}

	// Add the rest of the stastic
	result = result + "\n------------------------------------------\n";
	result = result + "Statistic:\n";
	result = result + "------------------------------------------\n";
	result = result + "Small (" + toString(minAreaSize) + ")\t" + toString(numberOfTooSmallParticles) + "\n";
	result = result + "Big (" + toString(maxAreaSize) + ")\t" + toString(numberOfTooBigParticles) + "\n";
	result = result + "Coloc    ;" + toString(numberOfColocEvs) + "\n";
	result = result + "Not Coloc;" + toString(numberOfNotColocEvs) + "\n";
	result = result + "GFP only;" + toString(numberOfGfpOnly) + "\n";
	result = result + "CY3 only;" + toString(numberOfCy3Only) + "\n";
	result = result + "GFP Evs;" + toString(numerOfFounfGfp) + "\n";
	result = result + "CY3 Evs;" + toString(numberOfFoundCy3) + "\n";


	File.saveString(result, output + File.separator + file + "_final.txt");

	retval = newArray(numberOfTooSmallParticles,numberOfTooBigParticles, numberOfColocEvs, numberOfNotColocEvs, numberOfGfpOnly, numberOfCy3Only, numerOfFounfGfp, numberOfFoundCy3);
	return retval;
}


///
/// Counts the EVs in the picture
/// The result is a value in range from [0, 255]
/// 0 is no coloc 255 is maximum coloc.
///
function countEvs(resultmeasure, output) {

	minAreaSize = settings[SETTING_MIN_PARTICLE_SIZE];
	maxAreaSize = settings[SETTING_MAX_PARTICLE_SIZE];

	read1 = File.openAsString(resultmeasure);
	lines1 = split(read1, "\n");

	result = "ROI; Area; Measure\n";

	numberOfTooSmallParticles = 0;
	numberOfTooBigParticles = 0;
	numberOfFoundEVs = 0;

	// First line is header therefore start with 1
	for (i = 1; i < lines1.length; i++) {

		linemeas = split(lines1[i], ",");
		if (linemeas[1] > minAreaSize) {
			if(linemeas[1] < maxAreaSize){

				a = parseFloat(linemeas[2]);

				//
				// Count the found EVs
				//
				if (a > 0) {
					numberOfFoundEVs++;
				}
				result = result + linemeas[0] + ";" + linemeas[1] + ";" + linemeas[2] + "\n";
			}else{
				numberOfTooBigParticles++;
			}
		} else {
			numberOfTooSmallParticles++;
		}
	}

	// Add the rest of the stastic
	result = result + "\n------------------------------------------\n";
	result = result + "Statistic:\n";
	result = result + "------------------------------------------\n";
	result = result + "Small (" + toString(minAreaSize) + ")\t" + toString(numberOfTooSmallParticles) + "\n";
	result = result + "Big (" + toString(maxAreaSize) + ")\t" + toString(numberOfTooBigParticles) + "\n";
	result = result + "Found Evs;" + toString(numberOfFoundEVs) + "\n";


	File.saveString(result, output + File.separator + file + "_final.txt");

	retval = newArray(numberOfTooSmallParticles,numberOfTooBigParticles, numberOfFoundEVs);
	return retval;
}


///
/// \brief Closes all open windows
///
function cleanUp() {
	roiManager("Delete");
	list = getList("window.titles");
	for (i = 0; i < list.length; i++) {
		winame = list[i];
		selectWindow(winame);
		run("Close");
	}
	close("*");
}

///
/// \brief Open GUI interface
///
function openGui() {

	inPath = input;
	outPath = output;

	Dialog.create("EV colocalizer");
	//Dialog.addString("Input path:", inPath);
	//Dialog.addString("Results path:", outPath);
	Dialog.addChoice("Number of channels:", newArray(2, 1));
	Dialog.addChoice("Green Channel:", newArray("C=0", "C=1"));
	Dialog.addChoice("Thresholding:", newArray("Li", "MaxEntropy"));
	Dialog.addCheckbox("Enhance contrast for C=0", false);
	Dialog.addCheckbox("Enhance contrast for C=1", true);
	Dialog.addCheckbox("Calculate Colocalization", true);
	Dialog.addNumber("Min particle size:", 0.05);
	Dialog.addNumber("Max particle size:", 9999999);
	Dialog.addMessage("(c) 2020 J.D. | Licensed under the MIT license");
	Dialog.show();

	//inPath = Dialog.getString();
	//outPath = Dialog.getString();
	nrOfChannels = Dialog.getChoice();
	greenChannel = Dialog.getChoice();
	thersholding = Dialog.getChoice();
	enhanceForC0 = Dialog.getCheckbox();
	enhanceForC1 = Dialog.getCheckbox();
	colocActive = Dialog.getCheckbox();
	minParticleSize = Dialog.getNumber();
	maxParticleSize = Dialog.getNumber();


	retval = newArray(inPath, outPath, nrOfChannels, greenChannel, enhanceForC0, enhanceForC1, minParticleSize, maxParticleSize, colocActive,thersholding);
	return retval;
}
