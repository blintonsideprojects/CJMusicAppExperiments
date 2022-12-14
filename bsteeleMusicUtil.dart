//  -v -o songs -x allSongs.songlyrics -a songs -f -w allSongs2.songlyrics
//  -v -o songs -x allSongs.songlyrics -a songs -f -w allSongs2.songlyrics -o songs2 -x allSongs2.songlyrics
//   -v -url http://www.bsteele.com/bsteeleMusicApp/allSongs.songlyrics -ninjam
//  -v -url http://www.bsteele.com/bsteeleMusicApp/allSongs.songlyrics
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:bsteeleMusicLib/songs/chordDescriptor.dart';
import 'package:bsteeleMusicLib/songs/chordSection.dart';
import 'package:bsteeleMusicLib/songs/section.dart';
import 'package:bsteeleMusicLib/songs/song.dart';
import 'package:bsteeleMusicLib/songs/songMetadata.dart';
import 'package:bsteeleMusicLib/songs/songPerformance.dart';
import 'package:bsteeleMusicLib/util/util.dart';
import 'package:english_words/english_words.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:quiver/collection.dart';
import 'package:string_similarity/string_similarity.dart';

import 'appLogger.dart';

const String _allSongPerformancesDirectoryLocation = 'communityJams/cj/Downloads';
const String _junkRelativeDirectory = 'junk'; //  relative to user home
const String _allSongDirectory = 'github/allSongs.songlyrics';
const String _allSongPerformancesGithubFileLocation = '$_allSongDirectory/allSongPerformances.songperformances';
const String _allSongsFileLocation = '$_allSongDirectory/allSongs.songlyrics';

void main(List<String> args) {
  Logger.level = Level.info;

  var util = BsteeleMusicUtil();
  util.runMain(args);
}

/// a command line utility to help manage song list maintenance
/// to and from tools like git and the bsteele Music App.
class BsteeleMusicUtil {
  /// help message to the user
  void _help() {
    print('''
bsteeleMusicUtil:
//  a utility for the bsteele Music App
arguments:
-a {file_or_dir}    add all the .songlyrics files to the utility's allSongs list 
-allSongPerformances sync with CJ performances
-cjwrite {file)     format the song metadata
-cjwritesongs {file)     write song list of cj songs
-cjread {file)      add song metadata
-cjcsvwrite {file}  format the song data as a CSV version of the CJ ranking metadata
-cjcsvread {file}   read a cj csv format the song metadata file
-expand {file}      expand a songlyrics list file to the output directory
-f                  force file writes over existing files
-h                  this help message
-html               HTML song list
-list               list all songs
-longlyrics         select for songs  with long lyrics lines
-longsections       select for songs  with long sections
-ninjam             select for ninjam friendly songs
-o {output dir}     select the output directory, must be specified prior to -x
-perfupdate {file}  update the song performances with a file
-perfwrite {file}   update the song performances to a file
-popSongs           list the most popular songs
-stat               statistics
-url {url}          read the given url into the utility's allSongs list
-user               list contributing users
-v                  verbose output utility's allSongs list
-V                  very verbose output
-w {file}           write the utility's allSongs list to the given file
-words              show word statistics
-x                  experimental
-xmas               filter for christmas songs
-meta               print a metadata entries

note: the output directory will NOT be cleaned prior to the expansion.
this means old and stale songs might remain in the directory.
note: the modification date and time of the songlyrics file will be 
coerced to reflect the songlist's last modification for that song.
''');
  }

  //-similar            list similar titled/artist songs

  /// A workaround to call the unix touch command to modify the
  /// read song's file to reflect it's last modification date in the song list.
  Future setLastModified(File file, int lastModified) async {
    var t = DateTime.fromMillisecondsSinceEpoch(lastModified);
    //print ('t: ${t.toIso8601String()}');
    //  print ('file.path: ${file.path}');
    await Process.run('bash', ['-c', 'touch --date="${t.toIso8601String()}" ${file.path}']).then((result) {
      stdout.write(result.stdout);
      stderr.write(result.stderr);
      if (result.exitCode != 0) {
        throw 'setLastModified() bad exit code: ${result.exitCode}';
      }
    });
  }

  /// A workaround method to get the async on main()
  void runMain(List<String> args) async {
    //  help if nothing to do
    if (args.isEmpty) {
      _help();
      return;
    }

    //  process the requests
    for (var argCount = 0; argCount < args.length; argCount++) {
      var arg = args[argCount];
      switch (arg) {
        case '-a':
        //  insist there is another arg
          if (argCount >= args.length - 1) {
            logger.e('missing directory path for -a');
            _help();
            exit(-1);
          }
          argCount++;
          {
            Directory inputDirectory = Directory(args[argCount]);

            if (inputDirectory.statSync().type == FileSystemEntityType.directory) {
              if (!(await inputDirectory.exists())) {
                logger.e('missing directory for -a');
                _help();
                exit(-1);
              }
              _addAllSongsFromDir(inputDirectory);
              continue;
            }
          }
          File inputFile = File(args[argCount]);
          logger.i('a: ${(await inputFile.exists())}, ${(await inputFile is Directory)}');

          if (!(await inputFile.exists()) && !(await inputFile is Directory)) {
            logger.e('missing input file/directory for -a: ${inputFile.path}');
            exit(-1);
          }
          _addAllSongsFromDir(inputFile);
          break;

        case '-copyright':
          _copyright();
          break;

//        case '-csv':
//          _csv();
//          break;
        case '-chordsearch':
          if (argCount >= args.length - 1) {
            logger.e('missing chord text for -cjchordsearch');
            _help();
            exit(-1);
          }
          argCount++;
          Directory inputDirectory = Directory(args[argCount]);
          _addAllSongsFromDir(inputDirectory);
          argCount++;

          String chordString = args[argCount]; 
          for (Song song in allSongs) {
              var chordSections = song.getChordSections();
              for (ChordSection chordSection in chordSections) {
                if (chordSection.toString().contains(chordString))
                {
                  print (song.title);
                  break;
                }
              }
          }
          break;
        case '-lyricsearch':
          if (argCount >= args.length - 1) {
            logger.e('missing chord text for -cjchordsearch');
            _help();
            exit(-1);
          }
          argCount++;
          Directory inputDirectory = Directory(args[argCount]);
          _addAllSongsFromDir(inputDirectory);
          argCount++;

          String lyricString = args[argCount]; 
          for (Song song in allSongs) {
              for (var lyricSection in song.lyricSections) 
              {
                var foundLyric = false;
                for (var line in lyricSection.lyricsLines) {
                  if (line.toLowerCase().contains(lyricString.toLowerCase()))
                  {
                    print (song.title);
                    foundLyric = true;
                    break;
                  }
                }
                if (foundLyric)
                {
                  break;
                }
              }
          }
          break;
        case '-cjread': // {file}
          //  insist there is another arg
          if (argCount >= args.length - 1) {
            logger.e('missing directory path for -a');
            _help();
            exit(-1);
          }
          argCount++;
          {
            Directory inputDirectory = Directory(args[argCount]);

            if (inputDirectory.statSync().type == FileSystemEntityType.directory) {
              if (!(await inputDirectory.exists())) {
                logger.e('missing directory for -a');
                _help();
                exit(-1);
              }
              _addAllSongsFromDir(inputDirectory);
              continue;
            }
          }
          File inputFile = File(args[argCount]);
          logger.i('a: ${(await inputFile.exists())}, ${(await inputFile is Directory)}');

          if (!(await inputFile.exists()) && !(await inputFile is Directory)) {
            logger.e('missing input file/directory for -a: ${inputFile.path}');
            exit(-1);
          }
          SongMetadata.fromJson(inputFile.readAsStringSync());
          break;

        case '-cjwrite': // {file)     format the song metadata
          //  assert there is another arg
          if (argCount >= args.length - 1) {
            logger.e('missing directory path for -a');
            exit(-1);
          }
          argCount++;
          {
            File outputFile = File(args[argCount]);

            if (await outputFile.exists() && !_force) {
              logger.e('"${outputFile.path}" already exists for -w without -f');
              exit(-1);
            }
            await outputFile.writeAsString(SongMetadata.toJson(), flush: true);
          }
          break;
        case '-cjwritesongs': // {file)
          //  assert there is another arg
          if (argCount >= args.length - 1) {
            logger.e('missing directory path for -a');
            exit(-1);
          }
          argCount++;
          {
            File outputFile = File(args[argCount]);

            if (await outputFile.exists() && !_force) {
              logger.e('"${outputFile.path}" already exists for -w without -f');
              exit(-1);
            }
            SplayTreeSet<Song> cjSongs = SplayTreeSet();
            for (Song song in allSongs) {
              var meta = SongMetadata.where(idIs: song.songId.songId, nameIs: 'cj');
              if (meta.isNotEmpty) {
                cjSongs.add(song);
                logger.i('"${song.songId.songId}", cj:${meta.first.nameValues.first.value}');
              }
            }

            logger.i('cjSongs: ${cjSongs.length}');

            await outputFile.writeAsString(Song.listToJson(cjSongs.toList()), flush: true);
          }
          break;
        case '-cjcsvwrite': // {file}  format the song data as a CSV version of the CJ ranking metadata
          //  assert there is another arg
          if (argCount >= args.length - 1) {
            logger.e('missing directory path for -a');
            exit(-1);
          }
          argCount++;
          {
            File outputFile = File(args[argCount]);

            if (await outputFile.exists() && !_force) {
              logger.e('"${outputFile.path}" already exists for -w without -f');
              exit(-1);
            }
            await outputFile.writeAsString(_cjCsvRanking(), flush: true);
          }
          break;
        case '-cjcsvread': // {file}
          //  insist there is another arg
          if (argCount >= args.length - 1) {
            logger.e('missing directory path for -a');
            _help();
            exit(-1);
          }
          argCount++;
          {
            Directory inputDirectory = Directory(args[argCount]);

            if (inputDirectory.statSync().type == FileSystemEntityType.directory) {
              if (!(await inputDirectory.exists())) {
                logger.e('missing directory for -a');
                _help();
                exit(-1);
              }
              _addAllSongsFromDir(inputDirectory);
              continue;
            }
          }
          File inputFile = File(args[argCount]);
          logger.i('a: ${(await inputFile.exists())}, ${(await inputFile is Directory)}');

          if (!(await inputFile.exists()) && !(await inputFile is Directory)) {
            logger.e('missing input file/directory for -a: ${inputFile.path}');
            exit(-1);
          }
          _cjCsvRead(inputFile.readAsStringSync());
          break;

        case '-exp':
          for (Song song in allSongs) {
            if (song.lastModifiedTime == 0) {
              print(song.toString());
            }
          }
          // for (Song song in allSongs) {
          //   var first = true;
          //   var lines = song.rawLyrics.split('\n');
          //   for (var i = 0; i < lines.length; i++) {
          //     var line = lines[i];
          //     if (line.contains('|')) {
          //       if ( first == true) {
          //         first = false;
          //         print('${song.title} by ${song.title}, songId: ${song.songId}');
          //       }
          //       print('   $i: $line');
          //     }
          //   }
          // }
          break;

        case '-expand':
          //  insist there is another arg
          if (argCount >= args.length - 1) {
            logger.e('missing file path for -x');
            _help();
            exit(-1);
          }

          argCount++;
          _file = File(args[argCount]);
          if (_file != null) {
            if (_verbose) print('input file path: ${_file.toString()}');
            if (!(await _file!.exists())) {
              logger.d('input file path: ${_file.toString()}'
                      ' is missing' +
                  (_outputDirectory.isAbsolute ? '' : ' at ${Directory.current}'));

              exit(-1);
            }

            if (_verbose) {
              logger.d('input file: ${_file.toString()}, file size: ${await _file!.length()}');
            }

            List<Song>? songs;
            if (_file!.path.endsWith('.zip')) {
              // Read the Zip file from disk.
              final bytes = await _file!.readAsBytes();

              // Decode the Zip file
              final archive = ZipDecoder().decodeBytes(bytes);

              // Extract the contents of the Zip archive
              for (final file in archive) {
                if (file.isFile) {
                  final data = file.content as List<int>;
                  songs = Song.songListFromJson(utf8.decode(data));
                }
              }
            } else {
              songs = Song.songListFromJson(_file!.readAsStringSync());
            }

            if (songs == null || songs.isEmpty) {
              logger.e('didn\'t find songs in ${_file.toString()}');
              exit(-1);
            }

            for (Song song in songs) {
              DateTime fileTime = DateTime.fromMillisecondsSinceEpoch(song.lastModifiedTime);

              //  used to spread the songs thinner than the maximum 1000 files
              //  per directory limit in github.com
              Directory songDir;
              {
                String s = song.getTitle().replaceAll(notWordOrSpaceRegExp, '').trim().substring(0, 1).toUpperCase();
                songDir = Directory(_outputDirectory.path + '/' + s);
              }
              songDir.createSync();

              File writeTo = File(songDir.path + '/' + song.songId.toString() + '.songlyrics');
              if (_verbose) logger.d('\t' + writeTo.path);
              String fileAsJson = song.toJsonAsFile();
              if (writeTo.existsSync()) {
                String fileAsRead = writeTo.readAsStringSync();
                if (fileAsJson != fileAsRead) {
                  writeTo.writeAsStringSync(fileAsJson, flush: true);
                  if (_verbose) {
                    logger.i(
                        '${song.getTitle()} by ${song.getArtist()}:  ${song.songId.toString()} ${fileTime.toIso8601String()}');
                  }
                } else {
                  if (_veryVerbose) {
                    logger.i(
                        '${song.getTitle()} by ${song.getArtist()}:  ${song.songId.toString()} ${fileTime.toIso8601String()}');
                    logger.i('\tidentical');
                  }
                }
              } else {
                if (_verbose) {
                  logger.i(
                      '${song.getTitle()} by ${song.getArtist()}:  ${song.songId.toString()} ${fileTime.toIso8601String()}');
                }
                writeTo.writeAsStringSync(fileAsJson, flush: true);
              }

              //  force the modification date
              await setLastModified(writeTo, fileTime.millisecondsSinceEpoch);
            }
          }
          break;

        case '-f':
          _force = true;
          break;

        case '-h':
          _help();
          break;

        case '-html':
          {
            print('''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>CJ Songlist</title>
	<style>
            .title {
                font-weight: bold
			}
            .artist {
				font-style: italic;
			}
 			.coverArtist {
				font-style: italic;
			}

        </style>
</head>
<body>
<h1>Community Jams Songlist</h1>
<ul>
''');
            for (Song song in allSongs) {
              print('<li><span class="title">${song.title}</span> by <span class="artist">${song.artist}</span>'
                  '${song.coverArtist.isNotEmpty ? ' cover by <span class="coverArtist">${song.coverArtist}</span>' : ''}'
                  '</li>');
            }
            print('''</ul>
</body>
</html>
''');
          }
          break;

        case '-list':
          for (Song song in allSongs) {
            print('${song.title} by ${song.title}, songId: ${song.songId}');
          }
          break;

        case '-longlyrics':
          {
            Map<Song, int> longLyrics = {};
            for (Song song in allSongs) {
              int maxLength = 0;
              for (var lyricSection in song.lyricSections) {
                for (var line in lyricSection.lyricsLines) {
                  maxLength = max(maxLength, line.length);
                }
              }
              if (maxLength > 60) {
                longLyrics[song] = maxLength;
              }
            }

            SplayTreeSet<int> sortedValues = SplayTreeSet();
            sortedValues.addAll(longLyrics.values);
            for (int i in sortedValues.toList(growable: false).reversed) {
              SplayTreeSet<Song> sortedSongs = SplayTreeSet();
              for (Song song in longLyrics.keys) {
                if (longLyrics[song] == i) {
                  sortedSongs.add(song);
                }
              }
              for (Song song in sortedSongs) {
                print('"${song.title}" by "${song.artist}"'
                    '${song.coverArtist.isNotEmpty ? ' cover by "${song.coverArtist}' : ''}'
                    ': maxLength: $i');
              }
            }
          }
          break;

        case '-longsections':
          {
            Map<Song, int> longSections = {};
            for (Song song in allSongs) {
              int maxLength = 0;
              for (var lyricSection in song.lyricSections) {
                maxLength = max(maxLength, lyricSection.lyricsLines.length);
                maxLength =
                    max(maxLength, song.findChordSectionByLyricSection(lyricSection)?.rowCount(expanded: true) ?? 0);
              }
              if (maxLength >= 10) {
                longSections[song] = maxLength;
              }
            }

            SplayTreeSet<int> sortedValues = SplayTreeSet();
            sortedValues.addAll(longSections.values);
            for (int i in sortedValues.toList(growable: false).reversed) {
              SplayTreeSet<Song> sortedSongs = SplayTreeSet();
              for (Song song in longSections.keys) {
                if (longSections[song] == i) {
                  sortedSongs.add(song);
                }
              }
              for (Song song in sortedSongs) {
                print('"${song.title}" by "${song.artist}"'
                    '${song.coverArtist.isNotEmpty ? ' cover by "${song.coverArtist}' : ''}'
                    ': maxLength: $i');
              }
            }
          }
          break;

        case '-ninjam':
          {
            Map<Song, int> ninjams = {};
            Map<Song, ChordSection> ninjamSections = {};

            for (Song song in allSongs) {
              ChordSection? firstChordSection;
              bool allSignificantChordSectionsMatch = true;

              var chordSections = song.getChordSections();
              if (chordSections.length == 1) {
                firstChordSection = chordSections.first;
              }

              for (ChordSection chordSection in chordSections) {
                switch (chordSection.sectionVersion.section.sectionEnum) {
                  case SectionEnum.intro:
                  case SectionEnum.outro:
                  case SectionEnum.tag:
                  case SectionEnum.coda:
                  case SectionEnum.bridge:
                    break;
                  default:
                    if (firstChordSection == null) {
                      firstChordSection = chordSection;
                    } else {
                      if (!listsEqual(firstChordSection.phrases, chordSection.phrases)) {
                        allSignificantChordSectionsMatch = false;
                        break;
                      }
                    }
                    break;
                }
                if (!allSignificantChordSectionsMatch) {
                  break;
                }
              }
              if (firstChordSection != null && allSignificantChordSectionsMatch) {
                int bars = firstChordSection.getTotalMoments();
                if (firstChordSection.phrases.length == 1 && firstChordSection.phrases[0].isRepeat()) {
                  bars = firstChordSection.phrases[0].measures.length;
                }
                ninjams[song] = song.timeSignature.beatsPerBar * bars;
                ninjamSections[song] = firstChordSection;
              }
            }

            SplayTreeSet<int> sortedValues = SplayTreeSet();
            sortedValues.addAll(ninjams.values);
            for (int i in sortedValues) {
              if (i > 48) {
                break;
              }
              SplayTreeSet<Song> sortedSongs = SplayTreeSet();
              for (Song song in ninjams.keys) {
                if (ninjams[song] == i) {
                  sortedSongs.add(song);
                }
              }
              for (Song song in sortedSongs) {
                print('"${song.title}" by "${song.artist}"'
                    '${song.coverArtist.isNotEmpty ? ' cover by "${song.coverArtist}' : ''}'
                    ':  /bpi ${i}  /bpm ${song.beatsPerMinute}  ${ninjamSections[song]?.toMarkup()}');
              }
            }
          }
          break;

        case '-o':
        //  assert there is another arg
          if (argCount < args.length - 1) {
            argCount++;
            _outputDirectory = Directory(args[argCount]);
            if (_verbose) {
              logger.d('output path: ${_outputDirectory.toString()}');
            }
            if (!(await _outputDirectory.exists())) {
              if (_verbose) {
                logger.d('output path: ${_outputDirectory.toString()}'
                        ' is missing' +
                    (_outputDirectory.isAbsolute ? '' : ' at ${Directory.current}'));
              }

              Directory parent = _outputDirectory.parent;
              if (!(await parent.exists())) {
                logger.d('parent path: ${parent.toString()}'
                        ' is missing' +
                    (_outputDirectory.isAbsolute ? '' : ' at ${Directory.current}'));
                return;
              }
              _outputDirectory.createSync();
            }
          } else {
            logger.e('missing output path for -o');
            _help();
            exit(-1);
          }
          break;

        case '-allSongPerformances':
          {
            //  read the local directory's list of song performance files
            AllSongPerformances allSongPerformances = AllSongPerformances();
            allSongPerformances.clear();
            assert(allSongPerformances.allSongPerformanceHistory.isEmpty);
            assert(allSongPerformances.allSongPerformances.isEmpty);
            assert(allSongPerformances.allSongPerformanceRequests.isEmpty);

            //  add the github version
            allSongPerformances.updateFromJsonString(
                File('${Util.homePath()}/$_allSongPerformancesGithubFileLocation').readAsStringSync());
            allSongPerformances
                .loadSongs(Song.songListFromJson(File('${Util.homePath()}/$_allSongsFileLocation').readAsStringSync()));

            logger.i('allSongPerformances.length: ${allSongPerformances.length}');
            logger.i('allSongPerformanceHistory.length: ${allSongPerformances.allSongPerformanceHistory.length}');
            logger.i('last sung: ${allSongPerformances.allSongPerformanceHistory.last.lastSungDateString}');
            var lastSungDateTime = allSongPerformances.allSongPerformanceHistory.last.lastSungDateTime;
            // truncate date time to day
            lastSungDateTime = DateTime(lastSungDateTime.year, lastSungDateTime.month, lastSungDateTime.day);
            logger.i('lastSungDateTime: $lastSungDateTime');

            var dir = Directory(Util.homePath() + '/' + _allSongPerformancesDirectoryLocation);
            SplayTreeSet<File> files = SplayTreeSet((key1, key2) => key1.path.compareTo(key2.path));
            for (var file in dir.listSync()) {
              if (file is File) {
                files.add(file);
              }
            }
            //  update from the all local files
            for (var file in files) {
              var name = file.path.split('/').last;
              var m = _allSongPerformancesRegExp.firstMatch(name);
              if (m != null) {
                logger.i(name);
                var date = Util.yyyyMMdd_HHmmssStringToDate(name);
                if (date.compareTo(lastSungDateTime) >= 0) {
                  logger.i('');
                  if (_verbose) {
                    print('process: file: $name');
                  }

                  //  clear all the requests so only the most current set is used
                  allSongPerformances.clearAllSongPerformanceRequests();

                  allSongPerformances.updateFromJsonString(file.readAsStringSync());
                  logger.i('allSongPerformances.length: ${allSongPerformances.length}');
                  logger.i('allSongPerformanceHistory.length: ${allSongPerformances.allSongPerformanceHistory.length}');
                } else {
                  if (_verbose) {
                    print('ignore:  file: $name');
                  }
                  logger.d('ignore:  file: $name');
                }
              }
            }

            //  workaround for early bad singer entries
                {
              //  most recent performances, less than a year
              final int lastSungLimit = DateTime.now().millisecondsSinceEpoch - Duration.millisecondsPerDay * 365;
              SplayTreeSet<SongPerformance> performanceDelete =
                  SplayTreeSet<SongPerformance>(SongPerformance.compareByLastSungSongIdAndSinger);
              for (var songPerformance in allSongPerformances.allSongPerformances) {
                if (!songPerformance.singer.contains(' ') ||
                    songPerformance.lastSung < lastSungLimit ||
                    songPerformance.singer.contains('Vikki') ||
                    songPerformance.singer.contains('Alicia C.') ||
                    songPerformance.singer.contains('Bob S.')) {
                  performanceDelete.add(songPerformance);
                }
              }
              for (var performance in performanceDelete) {
                logger.d('delete: $performance');
                allSongPerformances.removeSingerSong(performance.singer, performance.songIdAsString);
                assert(!allSongPerformances.allSongPerformances.contains(performance));
              }

              //  history
              performanceDelete.clear();
              for (var songPerformance in allSongPerformances.allSongPerformanceHistory) {
                if (!songPerformance.singer.contains(' ') ||
                    songPerformance.lastSung < lastSungLimit ||
                    songPerformance.singer.contains('Vikki') ||
                    songPerformance.singer.contains('Alicia C.') ||
                    songPerformance.singer.contains('Bob S.')) {
                  performanceDelete.add(songPerformance);
                }
              }
              for (var performance in performanceDelete) {
                logger.d('delete history: $performance');
                allSongPerformances.removeSingerSongHistory(performance);
                assert(!allSongPerformances.allSongPerformanceHistory.contains(performance));
              }
            }

            logger.i('allSongPerformances.length: ${allSongPerformances.length}');
            logger.i('allSongPerformanceHistory.length: ${allSongPerformances.allSongPerformanceHistory.length}');

            // File outputFile = File('allSongPerformances_proc_${Util.utcNow()}.songperformances');
            // //  don't expect a duplicate!
            File outputFile = File('${Util.homePath()}/$_junkRelativeDirectory/allSongPerformances.songperformances');
            try {
              outputFile.deleteSync();
            } catch (e) {
              logger.i(e.toString());
              //assert(false);
            }
            await outputFile.writeAsString(allSongPerformances.toJsonString(), flush: true);
            if (_verbose) {
              print('allSongPerformances location: ${outputFile.path}');
            }
          }
          break;

        case '-perfupdate':
        //  assert there is another arg
          if (argCount < args.length - 1) {
            argCount++;
            var file = File(args[argCount]);

            if (await file.exists()) {
              logger.i('\'${file.path}\' exists.');
              AllSongPerformances allSongPerformances = AllSongPerformances();
              logger.i('allSongPerformances: ${allSongPerformances.length}');
              allSongPerformances.updateFromJsonString(file.readAsStringSync());
              logger.i('allSongPerformances: ${allSongPerformances.length}');
            } else {
              logger.e('\'${file.path}\' does not exist.');
            }
          } else {
            logger.e('missing input path for -perf');
            _help();
            exit(-1);
          }
          break;

        case '-perfwrite': // {file)     format the song meta data
          //  assert there is another arg
          if (argCount >= args.length - 1) {
            logger.e('missing directory path for -perfwrite');
            exit(-1);
          }
          argCount++;
          {
            File outputFile = File(args[argCount]);

            if (await outputFile.exists() && !_force) {
              logger.e('"${outputFile.path}" already exists for -w without -f');
              exit(-1);
            }
            AllSongPerformances allSongPerformances = AllSongPerformances();
            await outputFile.writeAsString(allSongPerformances.toJsonString(), flush: true);
          }
          break;

        case '-popSongs': //     list the most popular songs
          {
            //  read the local directory's list of song performance files
            AllSongPerformances allSongPerformances = AllSongPerformances();

            //  add the github version
            allSongPerformances.updateFromJsonString(
                File('${Util.homePath()}/$_allSongPerformancesGithubFileLocation').readAsStringSync());

            //  load local songs
            allSongPerformances
                .loadSongs(Song.songListFromJson(File('${Util.homePath()}/$_allSongsFileLocation').readAsStringSync()));

            {
              var missingSongs = SplayTreeSet<String>();
              for (var performance in allSongPerformances.allSongPerformanceHistory) {
                if (performance.song == null) {
                  missingSongs.add(performance.songIdAsString);
                  var lowerId = performance.songIdAsString.toLowerCase();
                  BestMatch bestMatch =
                      StringSimilarity.findBestMatch(lowerId, allSongPerformances.songMap.keys.toList(growable: false));
                  logger.i('$lowerId:  ${bestMatch.bestMatch.target}: ${bestMatch.bestMatch.rating}');
                }
              }
              for (var s in missingSongs) {
                logger.i('missing song: $s');
              }
            }

            Map<Song, int> songCounts = {};
            for (var performance in allSongPerformances.allSongPerformanceHistory) {
              var song = performance.song;
              if (song != null) {
                var count = songCounts[song];
                songCounts[song] = (count == null ? 1 : count + 1);
              }
            }

            var sortMapByValue = Map.fromEntries(songCounts.entries.toList()
              ..sort((e1, e2) {
                int ret = -e1.value.compareTo(e2.value);
                if (ret != 0) {
                  return ret;
                }
                return e1.key.compareTo(e2.key);
              }));

            {
              int count = 0;
              int? timesSung;
              for (var entry in sortMapByValue.entries) {
                count++;
                if (count >= 40) {
                  if (timesSung == null) {
                    timesSung = entry.value;
                  } else if (timesSung > entry.value) {
                    break;
                  }
                }
                logger.i('$count: ${entry.key}: ${entry.value}');
              }
            }
          }
          break;

        case '-similar':
          logger.e('fix -similar');
          {
            Map<String, Song> map = {};
            for (Song song in allSongs) {
              map[song.songId.songId] = song;
            }
            List<String> keys = [];

            keys.addAll(map.keys);
            List<String> listed = [];
            for (Song song in allSongs) {
              if (listed.contains(song.songId.songId)) {
                continue;
              }
              BestMatch bestMatch = StringSimilarity.findBestMatch(song.songId.songId, keys);

              SplayTreeSet<Rating> ratingsOrdered = SplayTreeSet((Rating rating1, Rating rating2) {
                var r1 = rating1.rating ?? 0;
                var r2 = rating2.rating ?? 0;
                if (r1 == r2) {
                  return 0;
                }
                return r1 < r2 ? 1 : -1;
              });
              ratingsOrdered.addAll(bestMatch.ratings);

              for (Rating rating in ratingsOrdered) {
                var r = rating.rating ?? 0;
                if (r >= 1.0) {
                  continue;
                }
                if (r >= 0.8) {
                  print('"${song.title.toString()}" by ${song.artist.toString()}');
                  Song? similar = map[rating.target];
                  if (similar != null) {
                    print('"${similar.title.toString()}" by ${similar.artist.toString()}');
                    print(' ');
                  }
                  listed.add(rating.target ?? 'null');
                }
                break;
              }
            }
          }
          break;

        case '-stat':
          print('songs: ${allSongs.length}');
          print('updates: $_updateCount');
          {
            var covers = 0;
            for (var song in allSongs) {
              if (song.title.contains('cover')) {
                covers++;
              }
            }
            print('covers: $covers');
          }
          {
            var chordDescriptorUsageMap = <ChordDescriptor, int>{};
            for (var chordDescriptor in ChordDescriptor.values) {
              chordDescriptorUsageMap[chordDescriptor] = 0;
            }
            for (var song in allSongs) {
              for (var moment in song.songMoments) {
                for (var chord in moment.measure.chords) {
                  var chordDescriptor = chord.scaleChord.chordDescriptor;
                  var count = chordDescriptorUsageMap[chordDescriptor] ?? 0;
                  chordDescriptorUsageMap[chordDescriptor] = count + 1;
                }
              }
            }
            print('chordDescriptorUsageMap: ${chordDescriptorUsageMap.keys.length}');
            var sortedValues = SplayTreeSet<int>();
            sortedValues.addAll(chordDescriptorUsageMap.values);
            for (var usage in sortedValues.toList().reversed) {
              for (var key in chordDescriptorUsageMap.keys.where((e) => chordDescriptorUsageMap[e] == usage)) {
                print('   _${key.name}, //  ${chordDescriptorUsageMap[key]}');
              }
            }
          }
          break;

        case '-test':
          {
            DateTime t = DateTime.fromMillisecondsSinceEpoch(1570675021323);
            File file = File('/home/bob/junk/j');
            await setLastModified(file, t.millisecondsSinceEpoch);
          }
          break;

        case '-w':
        //  assert there is another arg
          if (argCount >= args.length - 1) {
            logger.e('missing directory path for -a');
            exit(-1);
          }
          argCount++;
          {
            File outputFile = File(args[argCount]);

            if (await outputFile.exists() && !_force) {
              logger.e('"${outputFile.path}" already exists for -w without -f');
              exit(-1);
            }
            if (allSongs.isEmpty) {
              logger.e('allSongs is empty for -w');
              exit(-1);
            }
            await outputFile.writeAsString(Song.listToJson(allSongs.toList()), flush: true);
          }
          break;

        case '-words':
          for (var song in allSongs) {
            logger.i('${song.title} by ${song.artist}:');

            for (var lyricSection in song.lyricSections) {
              logger.i('    ${lyricSection.sectionVersion} ${lyricSection.lyricsLines.length}');
              var lineNumber = 0;

              for (var line in lyricSection.lyricsLines) {
                lineNumber++;
                var syllableCount = 0;
                for (var word in line.split(_spaceRegexp)) {
                  if (word.isNotEmpty) {
                    syllableCount += syllables(word);
                    logger.i('            $lineNumber: $syllableCount: $line: <$word>');
                  }
                }
                logger.i('       $lineNumber: $syllableCount: $line');
              }
            }
          }

          break;

        case '-v':
          _verbose = true;
          Logger.level = Level.debug;
          break;

        case '-V':
          _verbose = true;
          _veryVerbose = true;
          Logger.level = Level.info;
          break;

        case '-url':
        //  assert there is another arg
          if (argCount >= args.length - 1) {
            logger.e('missing file path for -url');
            _help();
            exit(-1);
          }
          argCount++;
          String url = args[argCount];
          logger.d("url: '$url'");
          var authority = url.replaceAll(r'http://', '');
          var path = authority.replaceAll(RegExp(r'^[.\w]*/', caseSensitive: false), '');
          authority = authority.replaceAll(RegExp(r'/.*'), '');
          logger.d('authority: <$authority>, path: <$path>');
          List<Song> addSongs = Song.songListFromJson(utf8
                  .decode(await http.readBytes(Uri.http(authority, path)))
                  .replaceAll('": null,', '": "",')) //  cheap repair
              ;
          allSongs.addAll(addSongs);

          // {
          //   var count = 0;
          //   for (var song in allSongs) {
          //     count += song.isLyricsParseRequired ? 1 : 0;
          //   }
          //   logger.i('isLyricsParseRequired: $count');
          // }
          break;

        case '-users':
          {
            final Map<String, String> userCorrections = {
              'pillyweed': 'Shari',
              'Pillyweed': 'Shari',
              'shari': 'Shari',
              'Cassandra': 'Shari',
            };
            for (Song song in allSongs) {
              var newUser = userCorrections[song.user];
              if (newUser != null) {
                logger.i('${song.titleWithCover} from ${song.user} to ${newUser}');
                song.user = newUser;
              }
            }
          }
          {
            Map<String, int> userMap = {};
            for (Song song in allSongs) {
              var count = userMap[song.user];
              userMap[song.user] = count == null ? 1 : count + 1;
            }
            for (var user in SplayTreeSet<String>((key1, key2) {
              return -(userMap[key1] ?? 0).compareTo(userMap[key2] ?? 0);
            })
              ..addAll(userMap.keys)) {
              logger.i('$user: ${userMap[user]}');
            }
          }
          break;

        case '-x':
          var song = allSongs.firstWhere((song) => song.title.contains('25'));
          logger.i('${song.title}, ${song.artist}');
          {
            var sb = StringBuffer('Sections: ');
            for (var section in song.lyricSections) {
              sb.write('${section.sectionVersion.toString().replaceFirst(':', '')}, ');
            }
            logger.i(sb.toString());
          }

          logger.i(song.chordsToJsonTransportString());
          break;

        case '-xmas':
          final RegExp christmasRegExp = RegExp(r'.*christmas.*', caseSensitive: false);
          SongMetadata.clear();
          for (Song song in allSongs) {
            if (christmasRegExp.hasMatch(song.songId.songId)) {
              SongMetadata.set(SongIdMetadata(song.songId.songId, metadata: [NameValue('christmas', '')]));
            }
          }
          print(SongMetadata.toJson());
          break;

        case '-meta':
          {
            //  the ninjam list
            const List<String> list = [
              'All Along The Watchtower, cover by Jimi Hendrix',
              'Already Gone',
              'As Tears Go By',
              'Bad',
              'Bad Bad Leroy Brown',
              'Before You Accuse Me, cover by Eric Clapton',
              'Bittersweet Symphony',
              'Black Magic Woman',
              'Black Velvet Band',
              'Bohemian Like You',
              'California Stars',
              'Call Me The Breeze, cover by Lynyrd Skynyrd',
              "Can't You See",
              'Careless Whisper',
              'Closing Time',
              'Counting Stars',
              'Creep',
              'Crossroads',
              'Da Doo Ron Ron',
              'December',
              'Demons',
              'Fadeaway',
              "Fallin'",
              "Feelin' Alright, cover by Joe Cocker",
              'Fifteen Days Under the Hood',
              'Firework',
              'Fly Away',
              'Folsom Prison Blues',
              'Fooled Around and Fell in Love',
              "Free Fallin'",
              'Get Up Stand Up',
              'Give Me One Reason',
              'Head Like A Hole',
              'Heart-Shaped Box',
              'Helpless',
              'Hey Joe',
              'High And Dry',
              'Hit The Road Jack, cover by Ray Charles',
              'Horse With No Name',
              'I Know You Rider',
              'I Washed My Hands In Muddy Water',
              'I Will Follow',
              "I'll Fly Away",
              'Island in the Sun',
              "Isn't She Lovely",
              'Johnny B. Goode',
              'Keep Your Hands To Yourself',
              'Kids',
              "Kids Don't Stand A Chance",
              'Killing the Blues, cover by Robert Plant and Alison Krauss',
              "Knockin' on Heaven's Door",
              'Laid',
              'Late In The Evening',
              'Lean On Me',
              'Learning To Fly',
              'Let the Music Play',
              'Lodi',
              'Lonely Boy',
              'Louie Louie',
              'Mack The Knife',
              'Never Been To Spain',
              'New Orleans Is Sinking',
              'One Gun',
              'Paint It Black',
              'Payphone',
              'People Get Ready',
              'Place in the Sun',
              'Pride (In the Name of Love)',
              'Radioactive',
              'Rebel Yell',
              'Riptide',
              "Rock'n Me",
              'Rocky Raccoon',
              'Round Here',
              'Route 66',
              'Royals',
              'Sail (A.D.D.)',
              'Say',
              'Secrets',
              'Seminole Wind',
              'Shambala',
              'Shape of My Heart',
              'She Hates Me',
              'Simple Man',
              'Six Underground',
              'Smells Like Teen Spirit',
              'Someone You Loved',
              'St. James Infirmary Blues',
              'Stand By Me',
              'Steal My Sunshine',
              'Stir It Up',
              'Strange Brew',
              'Sunday Morning',
              'Sweet Home Alabama',
              'Sweet Jane',
              'Take the Money And Run',
              "Takin' Care Of Business",
              'Telling Stories',
              'Thank U',
              'General, The',
              'Middle, The',
              'Rose, The',
              'Thrill Is Gone, The',
              'Too Late for Goodbyes',
              'Tupelo Honey',
              'Twist and Shout, cover by The Beatles',
              'Uprising',
              'Wagon Wheel',
              'Waiting For My Man',
              'Waterfalls',
              'Werewolves Of London',
              'What I Got',
              'What I Like About You',
              "What It's Like",
              "What's Up",
              'When Doves Cry',
              'Where Did You Sleep Last Night, cover by Nirvana',
              'Who Will Save Your Soul',
              'With or Without You',
              "You Ain't Goin' Nowhere",
              'Your Love Keeps Lifting Me Higher',
              'Zombie',
            ];
            for (var title in list) {
              var songsFound =
                  allSongs.where((song) => song.title.toLowerCase() == title.toLowerCase()).toList(growable: false);
              if (songsFound.isEmpty) {
                logger.i('//  NOT FOUND: $title');
                continue;
              }
              if (songsFound.length > 1) {
                logger.i('//  MULTIPLES FOUND: $title');
                for (var song in songsFound) {
                  logger.i('//    ${song.title}');
                }
              }
              logger.i('{"id":"${songsFound[0].songId}","metadata":[{"name":"cj","value":"ninjam"}]},');
            }
          }
          break;

        default:
          logger.e('command not understood: "$arg"');
          exit(-1);
      }
    }

    exit(0);
  }

  void _addAllSongsFromDir(dynamic inputFile) {
    logger.i('$inputFile');
    if (inputFile is! Directory) {
      return;
    }

    List contents = inputFile.listSync();
    for (var file in contents) {
      _addAllSongsFromFile(file);
    }
    return;
  }

  void _addAllSongsFromFile(File inputFile) {
    logger.d('_addAllSongsFromFile: $inputFile');

    if (!inputFile.path.endsWith('.songlyrics')) return;
    if (_verbose) logger.i('$inputFile');

    //  fix for bad song lyric files
    String s = inputFile.readAsStringSync();
    s = s.replaceAll('": null,', '": "",');

    //  only add the most recent modification
    List<Song> addSongs = Song.songListFromJson(s);
    for (Song song in addSongs) {
      if (allSongs.contains(song)) {
        Song listSong = allSongs.firstWhere((value) => value.songId.compareTo(song.songId) == 0);
        if (song.lastModifiedTime > listSong.lastModifiedTime) {
          allSongs.remove(listSong);
          allSongs.add(song);
          _updateCount++;
        }
      } else {
        allSongs.add(song);
      }
    }
  }

  void _copyright() {
    Map<String, SplayTreeSet<Song>> copyrights = {};
    for (Song song in allSongs) {
      String? copyright = song.copyright.trim();
      if (copyright.isEmpty) {
        continue;
      }
      //print('${song.copyright} ${song.songId.toString()}');
      SplayTreeSet<Song>? set = copyrights[copyright];
      if (set == null) {
        set = SplayTreeSet();
        set.add(song);
        copyrights[copyright] = set;
      } else {
        set.add(song);
      }
    }

    SplayTreeSet<String> orderedKeys = SplayTreeSet();
    orderedKeys.addAll(copyrights.keys);
    for (String copyright in orderedKeys) {
      print('"$copyright"');
      for (Song song in copyrights[copyright] ?? {}) {
        print('\t${song.songId.toString()}');
      }
    }
  }

  String _cjCsvRanking() {
    StringBuffer sb = StringBuffer();
    sb.write('Id'
        ',ranking'
        '\n');
    for (Song song in allSongs) {
      var meta = SongMetadata.where(idIs: song.songId.songId, nameIs: 'cj');
      if (meta.isNotEmpty) {
        sb.write('"${song.songId.songId}","${meta.first.nameValues.first.value}"\n');
      }
    }
    return sb.toString();
  }

  void _cjCsvRead(String input) {
    int i = 0;
    for (String line in input.split('\n')) {
      if (i > 0) {
        List<String> ranking = line.split(_csvLineSplit);
        if (ranking[1].isNotEmpty) {
          logger.v('$i: ${ranking[0]}, ${ranking[1]}');
          SongMetadata.add(SongIdMetadata(ranking[0], metadata: <NameValue>[]..add(NameValue('cj', ranking[1]))));
        }
      }
      i++;
    }
    logger.d(SongMetadata.toJson());
  }

// void _csv() {
//   StringBuffer sb = StringBuffer();
//   sb.write('Title, Artist, Cover Artist'
//       ',User'
//       // ',Modified'
//       ',Copyright'
//       ',Key'
//       ',BPM'
//       ',Time'
//       '\n');
//   for (Song song in allSongs) {
//     sb.write('"${song.title}","${song.artist}","${song.coverArtist}"'
//         ',"${song.user}"'
//         //  ',"${song.lastModifiedTime??''}"'
//         ',"${song.copyright.substring(0, min(song.copyright.length, 80))}"'
//         ',"${song.key}"'
//         ',"${song.defaultBpm}"'
//         ',"${song.beatsPerBar}/${song.unitsPerMeasure}"'
//         '\n');
//   }
//
//   //print(sb.toString());
//   File writeTo = File(Util.homePath() + '/allSongs.csv');
//   writeTo.writeAsStringSync(sb.toString(), flush: true);
// }

  Directory _outputDirectory = Directory.current;
  SplayTreeSet<Song> allSongs = SplayTreeSet();
  File? _file;
  bool _verbose = false;
  bool _veryVerbose = false;
  bool _force = false; //  force a file write, even if it already exists
  int _updateCount = 0;
  static RegExp notWordOrSpaceRegExp = RegExp(r'[^\w\s]');
}

final RegExp _allSongPerformancesRegExp = RegExp(r'^allSongPerformances_(\d{8}_\d{6}).songperformances$');
final RegExp _csvLineSplit = RegExp(r'[,\r]');
final RegExp _spaceRegexp = RegExp(r'\W');
