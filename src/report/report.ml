(*
 * This file is part of Bisect.
 * Copyright (C) 2008-2012 Xavier Clerc.
 *
 * Bisect is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * Bisect is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *)

open ReportUtils


let main () =
  ReportArgs.parse ();
  if !ReportArgs.outputs = [] then begin
    ReportArgs.print_usage ();
    exit 0
  end;
  let data =
    match !ReportArgs.files, !ReportArgs.combine_expr with
    | [], None ->
        prerr_endline " *** warning: neither input file nor expression provided";
        exit 0
    | (_ :: _), None ->
        List.fold_right
          (fun s acc ->
            List.iter
              (fun (k, arr) ->
                let arr' = try (Hashtbl.find acc k) +| arr with Not_found -> arr in
                Hashtbl.replace acc k arr')
              (Common.read_runtime_data s);
            acc)
          !ReportArgs.files
          (Hashtbl.create 17)
    | [], Some expr ->
        (try
          Combine.eval expr
        with
        | Combine.Exception e ->
            Printf.eprintf " *** combine expression error: %s\n"
              (Combine.string_of_error e);
            exit 1
        | e ->
            Printf.eprintf " *** combine expression error: %s\n"
              (Printexc.to_string e);
            exit 1)
    | (_ :: _), Some _ ->
        prerr_endline " *** error: both input file(s) and expression provided";
        exit 1 in
  let verbose = if !ReportArgs.verbose then print_endline else ignore in
  let search_file l f =
    let fail () =
      if !ReportArgs.ignore_missing_files then None
      else
        raise (Sys_error (f ^ ": No such file or directory")) in
    let rec search = function
      | hd :: tl ->
          let f' = Filename.concat hd f in
          if Sys.file_exists f' then Some f' else search tl
      | [] -> fail () in
    if Filename.is_implicit f then
      search l
    else if Sys.file_exists f then
      Some f
    else
      fail () in
  let search_in_path = search_file !ReportArgs.search_path in
  let generic_output file conv =
    ReportGeneric.output verbose file conv search_in_path data in
  let write_output = function
    | ReportArgs.Html_output dir ->
        mkdirs dir;
        ReportHTML.output verbose dir
          !ReportArgs.tab_size !ReportArgs.title
          search_in_path data
    | ReportArgs.Xml_output file ->
        generic_output file (ReportXML.make ())
    | ReportArgs.Xml_emma_output file ->
        generic_output file (ReportXMLEmma.make ())
    | ReportArgs.Csv_output file ->
        generic_output file (ReportCSV.make !ReportArgs.separator)
    | ReportArgs.Text_output file ->
        generic_output file (ReportText.make !ReportArgs.summary_only)
    | ReportArgs.Dump_output file ->
        generic_output file (ReportDump.make ())
    | ReportArgs.Bisect_output file ->
      let write chan =
        let data =
          Hashtbl.fold
            (fun k v acc -> (k, v) :: acc)
            data
            [] in
        Common.write_runtime_data chan data in
      match file with
      | "-" -> set_binary_mode_out stdout true; write stdout
      | _ -> Common.try_out_channel true file write in
  List.iter write_output (List.rev !ReportArgs.outputs)

let () =
  try
    main ();
    exit 0
  with
  | Sys_error s ->
      Printf.eprintf " *** system error: %s\n" s;
      exit 1
  | Unix.Unix_error (e, _, _) ->
      Printf.eprintf " *** system error: %s\n" (Unix.error_message e);
      exit 1
  | Common.Invalid_file s ->
      Printf.eprintf " *** invalid file: '%s'\n" s;
      exit 1
  | Common.Unsupported_version s ->
      Printf.eprintf " *** unsupported file version: '%s'\n" s;
      exit 1
  | Common.Modified_file s ->
      Printf.eprintf " *** source file modified since instrumentation: '%s'\n" s;
      exit 1
  | e ->
      Printf.eprintf " *** error: %s\n" (Printexc.to_string e);
      exit 1
